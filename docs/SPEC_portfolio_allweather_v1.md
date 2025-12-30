# All Weather Portfolio EA (Milestone 1)

## Target allocation (default inputs)
- TLT.US: 0.40
- VTI.US: 0.30
- IEI.US: 0.15
- GLD.US: 0.10
- USO.US: 0.05

## Operational logic
### Bootstrap
- Triggered when no portfolio positions exist or account signature differs from state.
- Creates/adjusts LONG positions to reach target weights based on current equity.
- Sizing uses: `value_per_1lot = contract_size * ask` and `volume = target_value / value_per_1lot`.

### Monitor & rebalance
- Rebalance check every `InpRebalanceDays` (default 15 days) or earlier if any drift exceeds threshold.
- Drift = `|current_weight - target_weight|`.
- Default rebalance action: bring positions back to target weights.

### USO special rules
- Max weight: `InpUSOMaxWeight` (default 0.07).
- Drift threshold: `InpUSODriftThreshold` (default 0.02).
- Do not add USO if portfolio drawdown is below `-InpUSONoAddBelowDD`.

### Kill switch
- Maintain persistent `equity_high`.
- Drawdown `% = (equity - equity_high) / equity_high`.
- If drawdown <= `-InpMaxDD` the EA enters REVIEW_ONLY (no trades).

### Guardrails
- Free margin percent >= `InpMinFreeMarginPct`.
- Spread <= `InpMaxSpreadPoints`.
- Max turnover per rebalance <= `InpMaxTurnoverPct`.
- Max orders per cycle <= `InpMaxOrdersPerCycle`.

## State persistence
- File: `MQL5/Files/portfolio_bridge/state/AW_CFD_V1_state.json`.
- Fields: `schema_version`, `portfolio_id`, `run_id`, `account_signature`, `last_bootstrap_ts`, `last_rebalance_ts`, `equity_high`, `last_dd_pct`, `targets`.

## Logging
- Log file: `MQL5/Files/portfolio_bridge/logs/portfolio_log.txt`.
- Includes init, bootstrap, rebalance, kill switch, and symbol errors.

## Bridge placeholder
- When rebalance triggers, a proposal JSON is written to `MQL5/Files/portfolio_bridge/out/`.
- No waiting for AI responses in milestone 1.
