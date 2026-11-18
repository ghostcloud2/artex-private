package agent

import (
	"testing"

	"github.com/Autumn-27/norma/llm"
)

func TestFromEnvUsesManagedServiceWithoutExternalKey(t *testing.T) {
	t.Setenv("ARTEX_LLM_PROVIDER", "")
	t.Setenv("ARTEX_LLM_MODEL", "")
	t.Setenv("ARTEX_LLM_BASE_URL", "")
	t.Setenv("ANTHROPIC_API_KEY", "")
	t.Setenv("OPENAI_API_KEY", "")
	t.Setenv("MANUS_API_URL", "https://internal.example")
	t.Setenv("MANUS_API_KEY", "managed-key")
	t.Setenv("MANUS_LLM_MODEL", "internal-model")

	cfg, ok := FromEnv()
	if !ok {
		t.Fatal("managed service should configure the provider without an external key")
	}
	if cfg.Format != llm.FormatOpenAI {
		t.Fatalf("format = %q, want openai", cfg.Format)
	}
	if cfg.BaseURL != "https://internal.example/v1" {
		t.Fatalf("base URL = %q, want internal /v1 endpoint", cfg.BaseURL)
	}
	if cfg.APIKey != "managed-key" {
		t.Fatalf("API key = %q, want managed credential", cfg.APIKey)
	}
	if cfg.Model != "internal-model" {
		t.Fatalf("model = %q, want MANUS_LLM_MODEL", cfg.Model)
	}
}

func TestFromEnvKeepsExternalOpenAICompatibility(t *testing.T) {
	t.Setenv("ARTEX_LLM_PROVIDER", "openai")
	t.Setenv("ARTEX_LLM_MODEL", "custom-model")
	t.Setenv("ARTEX_LLM_BASE_URL", "https://gateway.example/v1")
	t.Setenv("OPENAI_API_KEY", "external-key")
	t.Setenv("MANUS_API_URL", "")
	t.Setenv("MANUS_API_KEY", "")

	cfg, ok := FromEnv()
	if !ok {
		t.Fatal("external OpenAI configuration should remain supported")
	}
	if cfg.APIKey != "external-key" || cfg.BaseURL != "https://gateway.example/v1" {
		t.Fatalf("external configuration changed: base=%q key=%q", cfg.BaseURL, cfg.APIKey)
	}
}
