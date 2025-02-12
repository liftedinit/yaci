package extractor

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/types/dynamicpb"

	"github.com/liftedinit/yaci/internal/utils"
	"github.com/schollz/progressbar/v3"

	"github.com/liftedinit/yaci/internal/models"
	"github.com/liftedinit/yaci/internal/output"
	"github.com/liftedinit/yaci/internal/reflection"
)

const (
	blockMethodFullName = "cosmos.tx.v1beta1.Service.GetBlockWithTxs"
	txMethodFullName    = "cosmos.tx.v1beta1.Service.GetTx"
)

func ExtractBlocksAndTransactions(ctx context.Context, grpcConn *grpc.ClientConn, resolver *reflection.CustomResolver, start, stop uint64, outputHandler output.OutputHandler, maxConcurrency, maxRetries uint) error {
	if start == stop {
		slog.Info("Extracting blocks and transactions", "height", start)
	} else {
		slog.Info("Extracting blocks and transactions", "range", fmt.Sprintf("[%d, %d]", start, stop))
	}

	bar := progressbar.NewOptions64(
		int64(stop-start+1),
		progressbar.OptionClearOnFinish(),
		progressbar.OptionSetDescription("Processing blocks..."),
		progressbar.OptionShowCount(),
		progressbar.OptionShowIts(),
		progressbar.OptionSetTheme(progressbar.Theme{
			Saucer:        "=",
			SaucerHead:    ">",
			SaucerPadding: " ",
			BarStart:      "[",
			BarEnd:        "]",
		}),
	)
	bar.RenderBlank()

	sem := make(chan struct{}, maxConcurrency)
	var wg sync.WaitGroup
	errCh := make(chan error, stop-start+1)

	for i := start; i <= stop; i++ {
		select {
		case <-ctx.Done():
			return nil
		default:
			sem <- struct{}{}
			wg.Add(1)

			blockHeight := i
			go func() {
				defer wg.Done()
				defer func() {
					<-sem
					_ = bar.Add(1)
				}()
				err := ProcessSingleBlockWithRetry(ctx, grpcConn, resolver, blockHeight, outputHandler, maxRetries)
				if err != nil {
					if !errors.Is(err, context.Canceled) {
						slog.Error("Failed to process block after 3 retries", "height", blockHeight, "error", err)
					}
					errCh <- fmt.Errorf("failed to process block %d: %w", blockHeight, err)
				}
			}()
		}
	}

	wg.Wait()
	close(errCh)

	bar.Finish()

	for err := range errCh {
		return fmt.Errorf("error while fetching blocks: %w", err)
	}

	return nil
}

func ProcessSingleBlockWithRetry(ctx context.Context, grpcConn *grpc.ClientConn, resolver *reflection.CustomResolver, blockHeight uint64, outputHandler output.OutputHandler, maxRetries uint) error {
	var err error
	for attempt := uint(1); attempt <= maxRetries; attempt++ {
		// Check if the context has been cancelled before starting
		if ctx.Err() != nil {
			return ctx.Err()
		}
		err = processSingleBlock(ctx, grpcConn, resolver, blockHeight, outputHandler)
		if err == nil {
			return nil
		}
		// Check if the context has been cancelled before retrying
		if ctx.Err() != nil {
			return ctx.Err()
		}
		// Wait before retrying
		slog.Debug("Retrying processing block", "height", blockHeight, "attempt", attempt, "error", err)
		select {
		// Check if the context has been cancelled during the sleep
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Duration(2*attempt) * time.Second):
		}
	}
	return err
}

func processSingleBlock(ctx context.Context, grpcConn *grpc.ClientConn, resolver *reflection.CustomResolver, blockHeight uint64, outputHandler output.OutputHandler) error {
	blockServiceName, blockMethodNameOnly, err := utils.ParseMethodFullName(blockMethodFullName)
	if err != nil {
		return fmt.Errorf("failed to parse block method full name: %w", err)
	}

	blockMethodDescriptor, err := resolver.FindMethodDescriptor(blockServiceName, blockMethodNameOnly)
	if err != nil {
		return fmt.Errorf("failed to find block method descriptor: %w", err)
	}

	blockFullMethodName := utils.BuildFullMethodName(blockMethodDescriptor)

	txServiceName, txMethodNameOnly, err := utils.ParseMethodFullName(txMethodFullName)
	if err != nil {
		return fmt.Errorf("failed to parse tx method full name: %w", err)
	}

	txMethodDescriptor, err := resolver.FindMethodDescriptor(txServiceName, txMethodNameOnly)
	if err != nil {
		return fmt.Errorf("failed to find tx method descriptor: %w", err)
	}

	txFullMethodName := utils.BuildFullMethodName(txMethodDescriptor)

	uo := protojson.UnmarshalOptions{
		Resolver: resolver,
	}

	mo := protojson.MarshalOptions{
		Resolver: resolver,
	}

	blockJsonParams := fmt.Sprintf(`{"height": %d}`, blockHeight)

	// Create the request message
	blockInputMsg := dynamicpb.NewMessage(blockMethodDescriptor.Input())

	if err := uo.Unmarshal([]byte(blockJsonParams), blockInputMsg); err != nil {
		return fmt.Errorf("failed to parse block input parameters: %w", err)
	}

	// Create the response message
	blockOutputMsg := dynamicpb.NewMessage(blockMethodDescriptor.Output())

	err = grpcConn.Invoke(ctx, blockFullMethodName, blockInputMsg, blockOutputMsg)
	if err != nil {
		return fmt.Errorf("error invoking block method: %w", err)
	}

	blockJsonBytes, err := mo.Marshal(blockOutputMsg)
	if err != nil {
		return fmt.Errorf("failed to marshal block response: %w", err)
	}

	block := &models.Block{
		ID:   blockHeight,
		Data: blockJsonBytes,
	}

	// Process transactions
	var data map[string]interface{}
	if err := json.Unmarshal(blockJsonBytes, &data); err != nil {
		return fmt.Errorf("failed to unmarshal block JSON: %w", err)
	}

	// Get txs from block, if any
	transactions, err := extractTransactions(ctx, grpcConn, data, txMethodDescriptor, txFullMethodName, uo, mo)
	if err != nil {
		return fmt.Errorf("failed to extract transactions from block: %w", err)
	}

	err = outputHandler.WriteBlockWithTransactions(ctx, block, transactions)
	if err != nil {
		return fmt.Errorf("failed to write block with transactions: %w", err)
	}

	return nil
}
