package mcp

import (
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/rhobs/obs-mcp/pkg/logs"
	"github.com/rhobs/obs-mcp/pkg/otelcol"
	"github.com/rhobs/obs-mcp/pkg/tools"
	"github.com/rhobs/obs-mcp/pkg/traces"
)

// ToolGroup holds a named category of tools for documentation generation.
type ToolGroup struct {
	Name  string
	Icon  string
	Tools []mcp.Tool
}

// AllTools returns all available MCP tools.
// When adding a new tool, add it to pkg/tools/definitions.go to keep both MCP and Toolset in sync, as well as docs.
func AllTools() []mcp.Tool {
	var all []mcp.Tool
	for _, g := range GroupedTools() {
		all = append(all, g.Tools...)
	}
	return all
}

// GroupedTools returns tools organized by category for documentation.
func GroupedTools() []ToolGroup {
	toMCP := func(defs []tools.ToolDefInterface) []mcp.Tool {
		out := make([]mcp.Tool, len(defs))
		for i, d := range defs {
			out[i] = *d.ToMCPTool()
		}
		return out
	}

	promDefs := tools.AllTools()
	var promTools, alertTools []mcp.Tool
	for _, t := range toMCP(promDefs) {
		switch t.Name {
		case "get_alerts", "get_silences":
			alertTools = append(alertTools, t)
		default:
			promTools = append(promTools, t)
		}
	}

	return []ToolGroup{
		{Name: "Prometheus / Thanos", Icon: "📈", Tools: promTools},
		{Name: "Alertmanager", Icon: "🔔", Tools: alertTools},
		{Name: "Tempo (Distributed Tracing)", Icon: "🔍", Tools: toMCP(traces.AllTools())},
		{Name: "Loki (Log Management)", Icon: "📋", Tools: toMCP(logs.AllTools())},
		{Name: "OpenTelemetry Collector", Icon: "⚙️", Tools: toMCP(otelcol.AllTools())},
	}
}

// Individual tool creation functions for backward compatibility and testing
func CreateListMetricsTool() mcp.Tool {
	return *tools.ListMetrics.ToMCPTool()
}

func CreateExecuteInstantQueryTool() mcp.Tool {
	return *tools.ExecuteInstantQuery.ToMCPTool()
}

func CreateExecuteRangeQueryTool() mcp.Tool {
	return *tools.ExecuteRangeQuery.ToMCPTool()
}

func CreateShowTimeseriesTool() mcp.Tool {
	// For UI purposes only, no additional data to be sent to the LLM context.
	return *tools.ShowTimeseries.ToMCPTool()
}

func CreateGetLabelNamesTool() mcp.Tool {
	return *tools.GetLabelNames.ToMCPTool()
}

func CreateGetLabelValuesTool() mcp.Tool {
	return *tools.GetLabelValues.ToMCPTool()
}

func CreateGetSeriesTool() mcp.Tool {
	return *tools.GetSeries.ToMCPTool()
}

func CreateGetAlertsTool() mcp.Tool {
	return *tools.GetAlerts.ToMCPTool()
}

func CreateGetSilencesTool() mcp.Tool {
	return *tools.GetSilences.ToMCPTool()
}

func CreateLokiLabelNamesTool() mcp.Tool {
	return *logs.LabelNamesTool.ToMCPTool()
}

func CreateLokiListInstancesTool() mcp.Tool {
	return *logs.ListInstancesTool.ToMCPTool()
}

func CreateLokiLabelValuesTool() mcp.Tool {
	return *logs.LabelValuesTool.ToMCPTool()
}

func CreateLokiQueryRangeTool() mcp.Tool {
	return *logs.QueryRangeTool.ToMCPTool()
}
