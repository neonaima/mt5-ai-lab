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
   double spread_points = SymbolSpreadPoints(symbol);
   return GuardrailsOk(cfg, free_margin_pct, spread_points, turnover_pct, orders_count, reason);
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

bool ExecuteBootstrap(CTrade &trade, PortfolioState &state, const PortfolioConfig &cfg)
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
      if(MathAbs(delta_value) <= 0.0)
         continue;
      string guard_reason = "";
      if(!SymbolGuardrailsOk(cfg, symbol, 0.0, orders_done, guard_reason))
      {
         LogMessage("Bootstrap guardrail: " + guard_reason);
         continue;
      }
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double value_per_lot = SymbolValuePerLot(symbol, price);
      if(value_per_lot <= 0.0)
         continue;
      double volume_raw = MathAbs(delta_value) / value_per_lot;
      double volume = NormalizeVolume(symbol, volume_raw);
      if(volume <= 0.0)
         continue;
      string comment = cfg.portfolio_id + "|" + symbol;
      trade.SetExpertMagicNumber(cfg.magic);
      bool result = false;
      if(delta_value > 0)
         result = trade.Buy(volume, symbol, price, 0.0, 0.0, comment);
      else
         result = trade.Sell(volume, symbol, SymbolInfoDouble(symbol, SYMBOL_BID), 0.0, 0.0, comment);
      if(result)
      {
         orders_done++;
         if(orders_done >= cfg.max_orders_per_cycle)
            break;
      }
   }
   state.last_bootstrap_ts = TimeCurrent();
   LogMessage("Bootstrap end");
   return true;
}

bool ExecuteRebalance(CTrade &trade, PortfolioState &state, const PortfolioConfig &cfg)
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
      if(MathAbs(delta_value) <= 0.0)
         continue;
      string guard_reason = "";
      if(!SymbolGuardrailsOk(cfg, symbol, turnover_pct, orders_done, guard_reason))
      {
         LogMessage("Rebalance guardrail: " + guard_reason);
         continue;
      }
      if(symbol == "USO.US" && delta_value > 0 && state.last_dd_pct <= -cfg.uso_no_add_below_dd)
      {
         LogMessage("USO add skipped due to drawdown guard");
         continue;
      }
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double value_per_lot = SymbolValuePerLot(symbol, price);
      if(value_per_lot <= 0.0)
         continue;
      double volume_raw = MathAbs(delta_value) / value_per_lot;
      double volume = NormalizeVolume(symbol, volume_raw);
      if(volume <= 0.0)
         continue;
      string comment = cfg.portfolio_id + "|" + symbol;
      trade.SetExpertMagicNumber(cfg.magic);
      bool result = false;
      if(delta_value > 0)
         result = trade.Buy(volume, symbol, price, 0.0, 0.0, comment);
      else
         result = trade.Sell(volume, symbol, SymbolInfoDouble(symbol, SYMBOL_BID), 0.0, 0.0, comment);
      if(result)
      {
         orders_done++;
         if(orders_done >= cfg.max_orders_per_cycle)
            break;
      }
   }
   state.last_rebalance_ts = TimeCurrent();
   LogMessage("Rebalance executed");
   return true;
}

#endif
