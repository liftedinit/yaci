package yaci

import (
	"fmt"

	"github.com/liftedinit/yaci/internal/output"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

var PostgresRunE = func(cmd *cobra.Command, args []string) error {
	connString := args[1]
	if connString == "" {
		return fmt.Errorf("connection string is required for PostgreSQL output")
	}

	outputHandler, err := output.NewPostgresOutputHandler(connString)
	if err != nil {
		return errors.WithMessage(err, "failed to create PostgreSQL output handler")
	}
	defer outputHandler.Close()

	return extract(args[0], outputHandler)
}

var PostgresCmd = &cobra.Command{
	Use:   "postgres [address] [psql-connection-string]",
	Short: "Extract chain data to a PostgreSQL database",
	Args:  cobra.ExactArgs(2),
	RunE:  PostgresRunE,
}
