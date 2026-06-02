package mcp

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/containers/kubernetes-mcp-server/pkg/kubernetes"
)

func TestAuthMiddleware(t *testing.T) {
	tests := []struct {
		name           string
		authHeader     string
		wantCtxValue   string
		wantNoCtxValue bool
	}{
		{
			name:         "bearer token is stored in context",
			authHeader:   "Bearer some-token",
			wantCtxValue: "Bearer some-token",
		},
		{
			name:           "empty header does not set context value",
			authHeader:     "",
			wantNoCtxValue: true,
		},
		{
			name:           "non-bearer header does not set context value",
			authHeader:     "some-raw-value",
			wantNoCtxValue: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var gotCtxValue any
			var ctxValueExists bool

			inner := http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
				gotCtxValue = r.Context().Value(kubernetes.OAuthAuthorizationHeader)
				ctxValueExists = gotCtxValue != nil
			})

			handler := authMiddleware(inner)

			req := httptest.NewRequest("GET", "/test", http.NoBody)
			if tt.authHeader != "" {
				req.Header.Set(string(kubernetes.OAuthAuthorizationHeader), tt.authHeader)
			}

			handler.ServeHTTP(httptest.NewRecorder(), req)

			if tt.wantNoCtxValue {
				if ctxValueExists {
					t.Errorf("expected no context value, got %q", gotCtxValue)
				}
				return
			}

			if !ctxValueExists {
				t.Fatal("expected context value to be set, but it was nil")
			}
			if gotCtxValue != tt.wantCtxValue {
				t.Errorf("context value = %q, want %q", gotCtxValue, tt.wantCtxValue)
			}
		})
	}
}
