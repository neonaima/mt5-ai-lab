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
   double max_turnover_pct;
   int rebalance_days;
   double drift_threshold;
   double uso_max_weight;
   double uso_drift_threshold;
   double uso_no_add_below_dd;
   double max_dd;
};

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

bool GuardrailsOk(const PortfolioConfig &cfg, double free_margin_pct, double spread_points, double turnover_pct, int orders_count, string &reason)
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
   if(turnover_pct > cfg.max_turnover_pct)
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

bool SymbolGuardrailsOk(const PortfolioConfig &cfg, string symbol, double turnover_pct, int orders_count, string &reason)
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
   if(turnover_pct > cfg.max_turnover_pct)
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
   for(int i=0; i<total; i++)
   {
      string symbol = state.targets[i].symbol;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      double current_weight = current_value / equity;
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
   int orders_done = 0;
   int total = ArraySize(state.targets);
   for(int i=0; i<total; i++)
   {
      string symbol = state.targets[i].symbol;
      if(!EnsureSymbolReady(symbol))
         continue;
      double target_weight = state.targets[i].weight;
      if(symbol == "USO.US")
         target_weight = MathMin(target_weight, cfg.uso_max_weight);
      double target_value = equity * target_weight;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      double delta_value = target_value - current_value;
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double value_per_lot = SymbolValuePerLot(symbol, price);
      double volume_raw = 0.0;
      if(value_per_lot > 0.0)
         volume_raw = MathAbs(delta_value) / value_per_lot;
      LogMessage(StringFormat("Bootstrap check: sym=%s target_w=%g equity=%g target_val=%g price=%g volume_raw=%g",
         symbol, target_weight, equity, target_value, price, volume_raw));
      if(MathAbs(delta_value) <= 0.0)
         continue;
      string guard_reason = "";
      if(!SymbolGuardrailsOk(cfg, symbol, 0.0, orders_done, guard_reason))
      {
         if(guard_reason != "")
            LogMessage("Bootstrap guardrail: " + guard_reason);
         continue;
      }
      if(value_per_lot <= 0.0)
         continue;
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
      bool result = false;
      if(delta_value > 0)
         result = trade_ref.Buy(volume, symbol, price, 0.0, 0.0, comment);
      else
         result = trade_ref.Sell(volume, symbol, SymbolInfoDouble(symbol, SYMBOL_BID), 0.0, 0.0, comment);
      if(result)
      {
         string side = (delta_value > 0.0 ? "BUY" : "SELL");
         double fill_price = (delta_value > 0.0 ? price : SymbolInfoDouble(symbol, SYMBOL_BID));
         LogMessage(StringFormat("%s placed sym=%s volume=%g price=%g target_w=%g", side, symbol, volume, fill_price, target_weight));
         orders_done++;
         if(orders_done >= cfg.max_orders_per_cycle)
            break;
      }
   }
   state.last_bootstrap_ts = TimeCurrent();
   LogMessage("Bootstrap end");
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
      double target_value = equity * target_weight;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      turnover += MathAbs(target_value - current_value);
   }
   double turnover_pct = turnover / equity;
   string reason = "";
   if(!SymbolGuardrailsOk(cfg, state.targets[0].symbol, turnover_pct, 0, reason))
   {
      LogMessage("Rebalance skipped: " + reason);
      return false;
   }
   WriteRebalanceProposal(state, "triggered");
   int orders_done = 0;
   bool any_trade = false;
   for(int i=0; i<total; i++)
   {
      string symbol = state.targets[i].symbol;
      if(!EnsureSymbolReady(symbol))
         continue;
      double target_weight = state.targets[i].weight;
      if(symbol == "USO.US")
         target_weight = MathMin(target_weight, cfg.uso_max_weight);
      double target_value = equity * target_weight;
      double current_value = PortfolioPositionValue(cfg.portfolio_id, cfg.magic, symbol);
      double delta_value = target_value - current_value;
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double value_per_lot = SymbolValuePerLot(symbol, price);
      double volume_raw = 0.0;
      if(value_per_lot > 0.0)
         volume_raw = MathAbs(delta_value) / value_per_lot;
      LogMessage(StringFormat("Rebalance check: sym=%s target_w=%g equity=%g target_val=%g price=%g volume_raw=%g",
         symbol, target_weight, equity, target_value, price, volume_raw));
      if(MathAbs(delta_value) <= 0.0)
         continue;
      string guard_reason = "";
      if(!SymbolGuardrailsOk(cfg, symbol, turnover_pct, orders_done, guard_reason))
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
      if(value_per_lot <= 0.0)
         continue;
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
      bool result = false;
      if(delta_value > 0)
         result = trade_ref.Buy(volume, symbol, price, 0.0, 0.0, comment);
      else
         result = trade_ref.Sell(volume, symbol, SymbolInfoDouble(symbol, SYMBOL_BID), 0.0, 0.0, comment);
      if(result)
      {
         string side = (delta_value > 0.0 ? "BUY" : "SELL");
         double fill_price = (delta_value > 0.0 ? price : SymbolInfoDouble(symbol, SYMBOL_BID));
         LogMessage(StringFormat("%s placed sym=%s volume=%g price=%g target_w=%g", side, symbol, volume, fill_price, target_weight));
         any_trade = true;
         orders_done++;
         if(orders_done >= cfg.max_orders_per_cycle)
            break;
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
