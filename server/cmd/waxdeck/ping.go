package main

import (
	"fmt"
	"net"
	"net/http"
	"time"
)

// pingServer is the container HEALTHCHECK: probe the server's health
// endpoint and report by exit code. The image ships no curl, so the
// binary dials itself, as `waxflow ping` does.
func pingServer(addr string) error {
	url, err := pingURL(addr)
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("health endpoint answered %d", resp.StatusCode)
	}
	return nil
}

// pingURL turns the listen address into a dialable health URL; a
// wildcard host means every interface, so dial the IPv4 loopback.
func pingURL(addr string) (string, error) {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return "", fmt.Errorf("listen address %q: %w", addr, err)
	}
	switch host {
	case "", "0.0.0.0", "::":
		host = "127.0.0.1"
	}
	return "http://" + net.JoinHostPort(host, port) + "/api/v1/health", nil
}
