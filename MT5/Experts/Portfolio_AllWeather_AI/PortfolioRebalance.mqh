#ifndef PORTFOLIO_REBALANCE_MQH
#define PORTFOLIO_REBALANCE_MQH

#include <Trade/Trade.mqh>
#include "PortfolioUtils.mqh"
#include "PortfolioState.mqh"
#include "PortfolioBridge.mqh"

struct PortfolioConfig
{
   string portfolio_id;
   long magic;
   int max_orders_per_cycle;
   double min_free_margin_pct;
   double max_spread_points;
   double max_turnover_pct_rebalance;
   double max_turnover_pct_bootstrap;
   int rebalance_days;
   double drift_threshold;
   double uso_max_weight;
   double uso_drift_threshold;
   double uso_no_add_below_dd;
   double max_dd;
   double capital_buffer_pct;
};

struct RebalanceDelta
{
   string symbol;
   double target_weight;
   double current_value;
   double target_value;
   double delta_value;
};

void SortDeltaIndices(int &indices[], int count, RebalanceDelta &deltas[], bool ascending)
{
   for(int i=0; i<count - 1; i++)
   {
      for(int j=i+1; j<count; j++)
      {
         double left = deltas[indices[i]].delta_value;
         double right = deltas[indices[j]].delta_value;
         bool swap = ascending ? (right < left) : (right > left);
         if(swap)
         {
            int tmp = indices[i];
            indices[i] = indices[j];
            indices[j] = tmp;
         }
      }
   }
}

int CountPortfolioPositions(const string portfolio_id, long magic)
{
   int count = 0;
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         string comment = PositionGetString(POSITION_COMMENT);
         if(pos_magic == magic && StringFind(comment, portfolio_id + "|") == 0)
            count++;
      }
   }
   return count;
}

bool PortfolioHasPositionSymbol(const string portfolio_id, long magic, string symbol)
{
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         string comment = PositionGetString(POSITION_COMMENT);
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         if(pos_magic == magic && pos_symbol == symbol && StringFind(comment, portfolio_id + "|") == 0)
            return true;
      }
   }
   return false;
}

double PortfolioPositionVolume(const string portfolio_id, long magic, string symbol)
{
   int total = PositionsTotal();
   for(int i=0; i<total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         long pos_magic = PositionGetInteger(POSITION_MAGIC);
         string comment = PositionGetString(POSITION_COMMENT);
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         if(pos_magic == magic && pos_symbol == symbol && StringFind(comment, portfolio_id + "|") == 0)
         {
            return PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return 0.0;
}

double PortfolioPositionValue(const string portfolio_id, long magic, string symbol)
{
   double volume = PortfolioPositionVolume(portfolio_id, magic, symbol);
   if(volume <= 0.0)
      return 0.0;
   double price = SymbolInfoDouble(symbol, SYMBOL_BID);
   return SymbolValuePerLot(symbol, price) * volume;
}

bool GuardrailsOk(const PortfolioConfig &cfg, double free_margin_pct, double spread_points, double turnover_pct, double max_turnover_pct, int orders_count, string &reason)
{
   if(free_margin_pct < cfg.min_free_margin_pct)
   {
      reason = "Free margin below threshold";
      return false;
   }
   if(spread_points > cfg.max_spread_points)
   {
      reason = "Spread above max";
      return false;
   }
   if(turnover_pct > max_turnover_pct)
   {
      reason = "Turnover above max";
      return false;
   }
   if(orders_count >= cfg.max_orders_per_cycle)
   {
      reason = "Max orders per cycle reached";
      return false;
   }
   return true;
}

bool SymbolGuardrailsOk(const PortfolioConfig &cfg, string symbol, double turnover_pct, double max_turnover_pct, int orders_count, string &reason)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
   {
      reason = "Equity <= 0";
      return false;
   }
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double free_margin_pct = (free_margin / equity) * 100.0;
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;
   double spread_price = ask - bid;
   double spread_points = spread_price / point;
   LogMessage(StringFormat("Spread check: sym=%s digits=%d bid=%g ask=%g point=%g spreadPrice=%g spreadPts=%g max=%g",
      symbol, digits, bid, ask, point, spread_price, spread_points, cfg.max_spread_points));
   if(bid <= 0.0 || ask <= 0.0)
   {
      LogMessage(StringFormat("Skip sym=%s reason=invalid_price bid=%g ask=%g", symbol, bid, ask));
      return false;
   }
   if(free_margin_pct < cfg.min_free_margin_pct)
   {
      double required_margin = equity * cfg.min_free_margin_pct / 100.0;
      LogMessage(StringFormat("Skip sym=%s reason=free_margin free=%g required=%g", symbol, free_margin, required_margin));
      return false;
   }
   if(spread_points > cfg.max_spread_points)
   {
      LogMessage(StringFormat("Skip sym=%s reason=spread spreadPts=%g max=%g", symbol, spread_points, cfg.max_spread_points));
      return false;
   }
   if(turnover_pct > max_turnover_pct)
   {
      reason = "Turnover above max";
      return false;
   }
   if(orders_count >= cfg.max_orders_per_cycle)
   {
      reason = "Max orders per cycle reached";
      return false;
   }
   return true;
}

bool RebalanceDue(const PortfolioState &state, const PortfolioConfig &cfg)
{
   if(state.last_rebalance_ts == 0)
      return true;
   int seconds = (int)(TimeCurrent() - state.last_rebalance_ts);
   if(seconds >= cfg.rebalance_days * 86400)
      return true;
   int total = ArraySize(state.targets);
   if(total == 0)
      return false;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return false;
   double investable_capital = equity * (1.0 - cfg.capital_buffer_pct);
   if(investable_capital <= 0.0)
      return false;
   for(int i=0; i<total; i++)
   {
      string symbol = state.targets[i].symbol;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      double current_weight = current_value / investable_capital;
      double target_weight = state.targets[i].weight;
      double drift = MathAbs(current_weight - target_weight);
      double threshold = cfg.drift_threshold;
      if(symbol == "USO.US")
         threshold = cfg.uso_drift_threshold;
      if(drift >= threshold)
         return true;
   }
   return false;
}

bool ExecuteBootstrap(CTrade &trade_ref, PortfolioState &state, const PortfolioConfig &cfg)
{
   LogMessage("Bootstrap start");
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
   {
      LogMessage("Bootstrap skipped: equity <= 0");
      return false;
   }
   double investable_capital = equity * (1.0 - cfg.capital_buffer_pct);
   if(investable_capital <= 0.0)
   {
      LogMessage("Bootstrap skipped: investable capital <= 0");
      return false;
   }
   double turnover = 0.0;
   int total = ArraySize(state.targets);
   if(total == 0)
   {
      LogMessage("Bootstrap skipped: no targets");
      return false;
   }
   RebalanceDelta deltas[];
   ArrayResize(deltas, total);
   int pos_count = 0;
   int neg_count = 0;
   int pos_indices[];
   int neg_indices[];
   for(int i=0; i<total; i++)
   {
      string symbol = state.targets[i].symbol;
      double target_weight = state.targets[i].weight;
      if(symbol == "USO.US")
         target_weight = MathMin(target_weight, cfg.uso_max_weight);
      double target_value = investable_capital * target_weight;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      double delta_value = target_value - current_value;
      deltas[i].symbol = symbol;
      deltas[i].target_weight = target_weight;
      deltas[i].current_value = current_value;
      deltas[i].target_value = target_value;
      deltas[i].delta_value = delta_value;
      LogMessage(StringFormat("Target calc: sym=%s curVal=%g tgtVal=%g delta=%g",
         symbol, current_value, target_value, delta_value));
      if(delta_value > 0.0)
      {
         ArrayResize(pos_indices, pos_count + 1);
         pos_indices[pos_count] = i;
         pos_count++;
      }
      else if(delta_value < 0.0)
      {
         ArrayResize(neg_indices, neg_count + 1);
         neg_indices[neg_count] = i;
         neg_count++;
      }
      turnover += MathAbs(delta_value);
   }
   double turnover_pct = turnover / equity;
   LogMessage(StringFormat("Turnover guardrail: phase=BOOTSTRAP_COMPLETION max=%g", cfg.max_turnover_pct_bootstrap));
   string reason = "";
   if(!SymbolGuardrailsOk(cfg, state.targets[0].symbol, turnover_pct, cfg.max_turnover_pct_bootstrap, 0, reason))
   {
      LogMessage("Bootstrap skipped: " + reason);
      return false;
   }
   bool completion_mode = (pos_count > 0 && neg_count > 0);
   if(neg_count > 0 && pos_count == 0)
      LogMessage("Bootstrap shrink-only mode: only negative deltas");
   if(neg_count > 0)
      SortDeltaIndices(neg_indices, neg_count, deltas, true);
   if(pos_count > 0)
      SortDeltaIndices(pos_indices, pos_count, deltas, false);
   int orders_done = 0;
   bool any_trade = false;
   if(neg_count > 0)
   {
      for(int i=0; i<neg_count; i++)
      {
         int idx = neg_indices[i];
         string symbol = deltas[idx].symbol;
         if(!EnsureSymbolReady(symbol))
            continue;
         double delta_value = deltas[idx].delta_value;
         double current_volume = PortfolioPositionVolume(cfg.portfolio_id, cfg.magic, symbol);
         if(current_volume <= 0.0)
            continue;
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double value_per_lot = SymbolValuePerLot(symbol, bid);
         if(value_per_lot <= 0.0)
            continue;
         double volume_raw = MathAbs(delta_value) / value_per_lot;
         volume_raw = MathMin(volume_raw, current_volume);
         string guard_reason = "";
         if(!SymbolGuardrailsOk(cfg, symbol, turnover_pct, cfg.max_turnover_pct_bootstrap, orders_done, guard_reason))
         {
            if(guard_reason != "")
               LogMessage("Bootstrap guardrail: " + guard_reason);
            continue;
         }
         double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         if(min_lot > 0.0 && volume_raw < min_lot)
         {
            LogMessage(StringFormat("Skip sym=%s reason=below_min_lot volume_raw=%g min_lot=%g", symbol, volume_raw, min_lot));
            continue;
         }
         double volume = NormalizeVolume(symbol, volume_raw);
         if(volume <= 0.0)
            continue;
         if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
            || SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
         {
            LogMessage(StringFormat("Skip sym=%s reason=trade_disabled", symbol));
            continue;
         }
         trade_ref.SetExpertMagicNumber(cfg.magic);
         bool result = trade_ref.PositionClosePartial(symbol, volume);
         if(!result)
            result = trade_ref.PositionClose(symbol);
         if(result)
         {
            LogMessage(StringFormat("Trade: action=REDUCE sym=%s vol=%g reason=bootstrap_completion", symbol, volume));
            orders_done++;
            any_trade = true;
            if(orders_done >= cfg.max_orders_per_cycle)
               break;
         }
      }
   }
   for(int i=0; i<pos_count; i++)
   {
      if(orders_done >= cfg.max_orders_per_cycle)
         break;
      int idx = pos_indices[i];
      string symbol = deltas[idx].symbol;
      if(!EnsureSymbolReady(symbol))
         continue;
      double delta_value = deltas[idx].delta_value;
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double value_per_lot = SymbolValuePerLot(symbol, price);
      if(value_per_lot <= 0.0)
         continue;
      double volume_raw = MathAbs(delta_value) / value_per_lot;
      string guard_reason = "";
      if(!SymbolGuardrailsOk(cfg, symbol, turnover_pct, cfg.max_turnover_pct_bootstrap, orders_done, guard_reason))
      {
         if(guard_reason != "")
            LogMessage("Bootstrap guardrail: " + guard_reason);
         continue;
      }
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(min_lot > 0.0 && volume_raw < min_lot)
      {
         LogMessage(StringFormat("Skip sym=%s reason=below_min_lot volume_raw=%g min_lot=%g", symbol, volume_raw, min_lot));
         continue;
      }
      double volume = NormalizeVolume(symbol, volume_raw);
      if(volume <= 0.0)
         continue;
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
         || SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      {
         LogMessage(StringFormat("Skip sym=%s reason=trade_disabled", symbol));
         continue;
      }
      string comment = cfg.portfolio_id + "|" + symbol;
      trade_ref.SetExpertMagicNumber(cfg.magic);
      bool result = trade_ref.Buy(volume, symbol, price, 0.0, 0.0, comment);
      if(result)
      {
         LogMessage(StringFormat("Trade: action=BUY sym=%s vol=%g reason=bootstrap_completion", symbol, volume));
         LogMessage(StringFormat("BUY placed sym=%s volume=%g price=%g target_w=%g", symbol, volume, price, deltas[idx].target_weight));
         orders_done++;
         any_trade = true;
      }
   }
   if(any_trade)
   {
      state.last_bootstrap_ts = TimeCurrent();
      LogMessage("Bootstrap end");
   }
   else
   {
      LogMessage("Bootstrap no-op (no trades placed)");
   }
   return true;
}

bool ExecuteRebalance(CTrade &trade_ref, PortfolioState &state, const PortfolioConfig &cfg)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
   {
      LogMessage("Rebalance skipped: equity <= 0");
      return false;
   }
   double investable_capital = equity * (1.0 - cfg.capital_buffer_pct);
   if(investable_capital <= 0.0)
   {
      LogMessage("Rebalance skipped: investable capital <= 0");
      return false;
   }
   double turnover = 0.0;
   int total = ArraySize(state.targets);
   if(total == 0)
   {
      LogMessage("Rebalance skipped: no targets");
      return false;
   }
   for(int i=0; i<total; i++)
   {
      string symbol = state.targets[i].symbol;
      double target_weight = state.targets[i].weight;
      if(symbol == "USO.US")
         target_weight = MathMin(target_weight, cfg.uso_max_weight);
      double target_value = investable_capital * target_weight;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      turnover += MathAbs(target_value - current_value);
   }
   double turnover_pct = turnover / equity;
   LogMessage(StringFormat("Turnover guardrail: phase=REBALANCE max=%g", cfg.max_turnover_pct_rebalance));
   string reason = "";
   if(!SymbolGuardrailsOk(cfg, state.targets[0].symbol, turnover_pct, cfg.max_turnover_pct_rebalance, 0, reason))
   {
      LogMessage("Rebalance skipped: " + reason);
      return false;
   }
   WriteRebalanceProposal(state, "triggered");
   int orders_done = 0;
   bool any_trade = false;
   RebalanceDelta deltas[];
   ArrayResize(deltas, total);
   int pos_count = 0;
   int neg_count = 0;
   int pos_indices[];
   int neg_indices[];
   for(int i=0; i<total; i++)
   {
      string symbol = state.targets[i].symbol;
      double target_weight = state.targets[i].weight;
      if(symbol == "USO.US")
         target_weight = MathMin(target_weight, cfg.uso_max_weight);
      double target_value = investable_capital * target_weight;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      double delta_value = target_value - current_value;
      deltas[i].symbol = symbol;
      deltas[i].target_weight = target_weight;
      deltas[i].current_value = current_value;
      deltas[i].target_value = target_value;
      deltas[i].delta_value = delta_value;
      LogMessage(StringFormat("Target calc: sym=%s curVal=%g tgtVal=%g delta=%g",
         symbol, current_value, target_value, delta_value));
      if(delta_value > 0.0)
      {
         ArrayResize(pos_indices, pos_count + 1);
         pos_indices[pos_count] = i;
         pos_count++;
      }
      else if(delta_value < 0.0)
      {
         ArrayResize(neg_indices, neg_count + 1);
         neg_indices[neg_count] = i;
         neg_count++;
      }
   }
   bool completion_mode = (pos_count > 0 && neg_count > 0);
   if(neg_count > 0 && pos_count == 0)
      LogMessage("Rebalance shrink-only mode: only negative deltas");
   if(neg_count > 0)
      SortDeltaIndices(neg_indices, neg_count, deltas, true);
   if(pos_count > 0)
      SortDeltaIndices(pos_indices, pos_count, deltas, false);
   if(neg_count > 0)
   {
      for(int i=0; i<neg_count; i++)
      {
         if(orders_done >= cfg.max_orders_per_cycle)
            break;
         int idx = neg_indices[i];
         string symbol = deltas[idx].symbol;
         if(!EnsureSymbolReady(symbol))
            continue;
         double delta_value = deltas[idx].delta_value;
         double current_volume = PortfolioPositionVolume(cfg.portfolio_id, cfg.magic, symbol);
         if(current_volume <= 0.0)
            continue;
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double value_per_lot = SymbolValuePerLot(symbol, bid);
         if(value_per_lot <= 0.0)
            continue;
         double volume_raw = MathAbs(delta_value) / value_per_lot;
         volume_raw = MathMin(volume_raw, current_volume);
         string guard_reason = "";
         if(!SymbolGuardrailsOk(cfg, symbol, turnover_pct, cfg.max_turnover_pct_rebalance, orders_done, guard_reason))
         {
            if(guard_reason != "")
               LogMessage("Rebalance guardrail: " + guard_reason);
            continue;
         }
         double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         if(min_lot > 0.0 && volume_raw < min_lot)
         {
            LogMessage(StringFormat("Skip sym=%s reason=below_min_lot volume_raw=%g min_lot=%g", symbol, volume_raw, min_lot));
            continue;
         }
         double volume = NormalizeVolume(symbol, volume_raw);
         if(volume <= 0.0)
            continue;
         if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
            || SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
         {
            LogMessage(StringFormat("Skip sym=%s reason=trade_disabled", symbol));
            continue;
         }
         trade_ref.SetExpertMagicNumber(cfg.magic);
         bool result = trade_ref.PositionClosePartial(symbol, volume);
         if(!result)
            result = trade_ref.PositionClose(symbol);
         if(result)
         {
            if(completion_mode)
               LogMessage(StringFormat("Trade: action=REDUCE sym=%s vol=%g reason=bootstrap_completion", symbol, volume));
            LogMessage(StringFormat("SELL placed sym=%s volume=%g price=%g target_w=%g", symbol, volume, bid, deltas[idx].target_weight));
            any_trade = true;
            orders_done++;
         }
      }
   }
   for(int i=0; i<pos_count; i++)
   {
      if(orders_done >= cfg.max_orders_per_cycle)
         break;
      int idx = pos_indices[i];
      string symbol = deltas[idx].symbol;
      if(!EnsureSymbolReady(symbol))
         continue;
      double delta_value = deltas[idx].delta_value;
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double value_per_lot = SymbolValuePerLot(symbol, price);
      if(value_per_lot <= 0.0)
         continue;
      double volume_raw = MathAbs(delta_value) / value_per_lot;
      string guard_reason = "";
      if(!SymbolGuardrailsOk(cfg, symbol, turnover_pct, cfg.max_turnover_pct_rebalance, orders_done, guard_reason))
      {
         if(guard_reason != "")
            LogMessage("Rebalance guardrail: " + guard_reason);
         continue;
      }
      if(symbol == "USO.US" && delta_value > 0 && state.last_dd_pct <= -cfg.uso_no_add_below_dd)
      {
         LogMessage("USO add skipped due to drawdown guard");
         continue;
      }
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(min_lot > 0.0 && volume_raw < min_lot)
      {
         LogMessage(StringFormat("Skip sym=%s reason=below_min_lot volume_raw=%g min_lot=%g", symbol, volume_raw, min_lot));
         continue;
      }
      double volume = NormalizeVolume(symbol, volume_raw);
      if(volume <= 0.0)
         continue;
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)
         || SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      {
         LogMessage(StringFormat("Skip sym=%s reason=trade_disabled", symbol));
         continue;
      }
      string comment = cfg.portfolio_id + "|" + symbol;
      trade_ref.SetExpertMagicNumber(cfg.magic);
      bool result = trade_ref.Buy(volume, symbol, price, 0.0, 0.0, comment);
      if(result)
      {
         if(completion_mode)
            LogMessage(StringFormat("Trade: action=BUY sym=%s vol=%g reason=bootstrap_completion", symbol, volume));
         LogMessage(StringFormat("BUY placed sym=%s volume=%g price=%g target_w=%g", symbol, volume, price, deltas[idx].target_weight));
         any_trade = true;
         orders_done++;
      }
   }
   if(any_trade)
   {
      state.last_rebalance_ts = TimeCurrent();
      LogMessage("Rebalance executed");
   }
   else
   {
      LogMessage("Rebalance no-op (no trades placed)");
   }
   return true;
}

#endif
