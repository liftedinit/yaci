package metrics

import (
	"database/sql"
	"log/slog"
	"net/http"

	"github.com/liftedinit/yaci/internal/metrics/collectors"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

func CreateMetricsServer(db *sql.DB, bech32Prefix, addr string) error {
	collector := []prometheus.Collector{
		collectors.NewTotalTransactionCountCollector(db),
		collectors.NewTotalUniqueAddressesCollector(db, bech32Prefix)}
	prometheus.MustRegister(collector...)

	errChan := listen(addr)

	select {
	case err := <-errChan:
		if err != nil {
			return err
		}
	default:
	}

	return nil
}

func listen(addr string) chan error {
	errChan := make(chan error)
	go func() {
		http.Handle("/metrics", promhttp.Handler())
		if err := http.ListenAndServe(addr, nil); err != nil {
			slog.Error("Failed to start metrics server", "error", err)
			errChan <- err
		}
	}()

	return errChan
}
