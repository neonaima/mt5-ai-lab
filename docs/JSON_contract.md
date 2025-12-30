# Portfolio Bridge JSON Contract (Milestone 1)

## Folder layout
- `MQL5/Files/portfolio_bridge/in/` — reserved for inbound messages (unused in milestone 1).
- `MQL5/Files/portfolio_bridge/out/` — outbound proposals from EA.
- `MQL5/Files/portfolio_bridge/logs/` — EA logs.
- `MQL5/Files/portfolio_bridge/state/` — persistent state file.

## State file schema
Path example: `MQL5/Files/portfolio_bridge/state/AW_CFD_V1_state.json`

```json
{
  "schema_version": 1,
  "portfolio_id": "AW_CFD_V1",
  "run_id": "20240201_120501",
  "account_signature": {
    "login": 12345678,
    "server": "ActivTrades-Demo"
  },
  "last_bootstrap_ts": 1706780000,
  "last_rebalance_ts": 1708000000,
  "equity_high": 10000.0,
  "last_dd_pct": -0.0345,
  "targets": [
    { "symbol": "TLT.US", "weight": 0.40 },
    { "symbol": "VTI.US", "weight": 0.30 },
    { "symbol": "IEI.US", "weight": 0.15 },
    { "symbol": "GLD.US", "weight": 0.10 },
    { "symbol": "USO.US", "weight": 0.05 }
  ]
}
```

## Rebalance proposal (placeholder)
Path example: `MQL5/Files/portfolio_bridge/out/AW_CFD_V1_proposal.json`

```json
{
  "portfolio_id": "AW_CFD_V1",
  "run_id": "20240201_120501",
  "timestamp": "2024.02.01 12:05:01",
  "reason": "triggered",
  "targets": [
    { "symbol": "TLT.US", "weight": 0.40 },
    { "symbol": "VTI.US", "weight": 0.30 },
    { "symbol": "IEI.US", "weight": 0.15 },
    { "symbol": "GLD.US", "weight": 0.10 },
    { "symbol": "USO.US", "weight": 0.05 }
  ]
}
```
