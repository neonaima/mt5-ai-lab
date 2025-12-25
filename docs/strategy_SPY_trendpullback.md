# SPY H4 Trend Pullback — Step1 (logger only)

## Scope
Step1 = logger only. The Expert Advisor does **not** trade, send orders, or manage positions. It only evaluates signals on SPY.US H4 and logs outcomes.

## Inputs
- **InpSymbol**: symbol to evaluate (empty = current chart symbol)
- **InpTimeframe**: timeframe to evaluate (default H4)
- **InpFastEMA**: 20
- **InpSlowEMA**: 50
- **InpRSIPeriod**: 14
- **InpATRPeriod**: 14
- **InpADXPeriod**: 14
- **InpADXMin**: 18.0
- **InpATRMinPct**: 0.006 (0.6% of price)
- **InpRSILongMin**: 40.0
- **InpRSILongMax**: 50.0
- **InpRSIShortMin**: 50.0
- **InpRSIShortMax**: 60.0
- **InpPullbackMaxDistATR**: 0.35
- **InpLogToFile**: true/false
- **InpFileName**: mt5_spy_signals.jsonl

## Evaluation timing
- Only evaluate **once per new closed bar** on the selected timeframe.
- All indicators and prices are taken from **bar index 1**.

## Indicators (bar index 1)
- EMA20, EMA50 (iMA)
- RSI14 (iRSI)
- ATR14 (iATR)
- ADX14 main line (iADX)
- Close price (iClose)

## Regime filter
A bar is eligible only if **both** are true:
- ADX >= 18.0
- ATR / Close >= 0.006

If either condition fails, decision = **REGIME_BLOCK**.

## Bias rules
- **Long bias**: EMA20 > EMA50 **and** Close > EMA20
- **Short bias**: EMA20 < EMA50 **and** Close < EMA20

If neither bias is true, decision = **BIAS_BLOCK**.

## Pullback setup
Distance check (applies to both long and short):
- abs(Close - EMA20) <= 0.35 * ATR

### Long setup
Requires:
- Long bias
- RSI in [40, 50]
- Distance check passes

If true, decision = **LONG_SETUP**.

### Short setup
Requires:
- Short bias
- RSI in [50, 60]
- Distance check passes

If true, decision = **SHORT_SETUP**.

If regime is OK and bias is OK but setup conditions are not met, decision = **NO_SETUP**.

## Logging
- Always prints a single structured line per evaluated bar:

```
AI_SPY_TP_LOG | 2025-12-25 14:00 | SPY.US H4 | close=... ema20=... ema50=... rsi=... atr=... adx=... | decision=LONG_SETUP
```

- If `InpLogToFile = true`, append a JSON line to `MQL5/Files/<InpFileName>` with fields:
  - `ts`, `symbol`, `timeframe`, `close`, `ema20`, `ema50`, `rsi`, `atr`, `adx`, `regime_ok`, `bias`, `decision`
