package nativebridge

import (
	"encoding/json"
	"testing"
)

func TestBodyReadinessSurvivesDesktopForwarding(t *testing.T) {
	for _, expected := range []bool{false, true} {
		input, _ := json.Marshal(map[string]any{"ready": true, "article_ready": expected, "accounts": []any{}})
		var state Status
		if err := json.Unmarshal(input, &state); err != nil {
			t.Fatal(err)
		}
		output, err := json.Marshal(state)
		if err != nil {
			t.Fatal(err)
		}
		var forwarded map[string]any
		if err = json.Unmarshal(output, &forwarded); err != nil {
			t.Fatal(err)
		}
		if forwarded["article_ready"] != expected {
			t.Fatalf("readiness lost in forwarding: %s", output)
		}
	}
}
