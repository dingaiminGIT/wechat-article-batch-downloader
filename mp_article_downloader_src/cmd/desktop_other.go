//go:build !darwin

package cmd

import "context"

func watchDesktopParent(ctx context.Context, stop context.CancelFunc) {}
