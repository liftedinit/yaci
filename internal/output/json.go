package output

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/liftedinit/cosmos-dump/internal/models"
	"github.com/pkg/errors"
)

type JSONOutputHandler struct {
	blockDir string
	txDir    string
}

func NewJSONOutputHandler(outDir string) (*JSONOutputHandler, error) {
	blockDir := filepath.Join(outDir, "block")
	txDir := filepath.Join(outDir, "txs")

	err := os.MkdirAll(blockDir, 0755)
	if err != nil {
		return nil, errors.WithMessage(err, "failed to create blocks directory")
	}

	err = os.MkdirAll(txDir, 0755)
	if err != nil {
		return nil, errors.WithMessage(err, "failed to create transactions directory")
	}

	return &JSONOutputHandler{
		blockDir: blockDir,
		txDir:    txDir,
	}, nil
}

func (h *JSONOutputHandler) WriteBlock(ctx context.Context, block *models.Block) error {
	fileName := fmt.Sprintf("block_%010d.json", block.ID)
	filePath := filepath.Join(h.blockDir, fileName)
	return os.WriteFile(filePath, block.Data, 0644)
}

func (h *JSONOutputHandler) WriteTransaction(ctx context.Context, tx *models.Transaction) error {
	fileName := fmt.Sprintf("tx_%s.json", tx.Hash)
	filePath := filepath.Join(h.txDir, fileName)
	return os.WriteFile(filePath, tx.Data, 0644)
}

func (h *JSONOutputHandler) Close() error {
	return nil
}
