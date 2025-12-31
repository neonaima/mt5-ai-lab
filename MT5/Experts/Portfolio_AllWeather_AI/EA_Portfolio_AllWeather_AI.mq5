#property strict

#include <Trade/Trade.mqh>
#include "PortfolioUtils.mqh"
#include "PortfolioState.mqh"
#include "PortfolioRebalance.mqh"
#include "PortfolioBridge.mqh"

input string InpPortfolioId = "AW_CFD_V1";
input int InpMagicBase = 81001;

input double InpWeightTLT = 0.40;
input double InpWeightVTI = 0.30;
input double InpWeightIEI = 0.15;
input double InpWeightGLD = 0.10;
input double InpWeightUSO = 0.05;

input int InpRebalanceDays = 15;
input double InpDriftThreshold = 0.04;
input double InpUSOMaxWeight = 0.07;
input double InpUSODriftThreshold = 0.02;
input double InpUSONoAddBelowDD = 0.05;
input double InpMaxDD = 0.12;

input double InpCapitalBufferPct = 0.30; // 30% non investito

input double InpMinFreeMarginPct = 70.0;
input double InpMaxSpreadPoints = 25.0;
input double InpMaxTurnoverPct_Rebalance = 0.15;
input double InpMaxTurnoverPct_Bootstrap = 0.80;
input int InpMaxOrdersPerCycle = 6;
input double InpMinTradeValue = 50.0; // valuta del conto, default 50

CTrade trade;
PortfolioState g_state;
PortfolioConfig g_cfg;

void SetTargetsFromInputs(PortfolioState &state)
{
   ArrayResize(state.targets, 5);
   state.targets[0].symbol = "TLT.US";
   state.targets[0].weight = InpWeightTLT;
   state.targets[1].symbol = "VTI.US";
   state.targets[1].weight = InpWeightVTI;
   state.targets[2].symbol = "IEI.US";
   state.targets[2].weight = InpWeightIEI;
   state.targets[3].symbol = "GLD.US";
   state.targets[3].weight = InpWeightGLD;
   state.targets[4].symbol = "USO.US";
   state.targets[4].weight = InpWeightUSO;
}

void UpdateConfig()
{
   g_cfg.portfolio_id = InpPortfolioId;
   g_cfg.magic = InpMagicBase;
   g_cfg.max_orders_per_cycle = InpMaxOrdersPerCycle;
   g_cfg.min_free_margin_pct = InpMinFreeMarginPct;
   g_cfg.max_spread_points = InpMaxSpreadPoints;
   g_cfg.max_turnover_pct_rebalance = InpMaxTurnoverPct_Rebalance;
   g_cfg.max_turnover_pct_bootstrap = InpMaxTurnoverPct_Bootstrap;
   g_cfg.rebalance_days = InpRebalanceDays;
   g_cfg.drift_threshold = InpDriftThreshold;
   g_cfg.uso_max_weight = InpUSOMaxWeight;
   g_cfg.uso_drift_threshold = InpUSODriftThreshold;
   g_cfg.uso_no_add_below_dd = InpUSONoAddBelowDD;
   g_cfg.max_dd = InpMaxDD;
   g_cfg.capital_buffer_pct = InpCapitalBufferPct;
   g_cfg.min_trade_value = InpMinTradeValue;
}

void UpdateDrawdown(PortfolioState &state)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(state.equity_high <= 0.0)
      state.equity_high = equity;
   if(equity > state.equity_high)
      state.equity_high = equity;
   if(state.equity_high > 0.0)
      state.last_dd_pct = (equity - state.equity_high) / state.equity_high;
}

bool KillSwitchActive(const PortfolioState &state, const PortfolioConfig &cfg)
{
   return state.last_dd_pct <= -cfg.max_dd;
}

double PortfolioPositionVolumeByMagic(const string sym, long magic)
{
   double total_volume = 0.0;
   int total_positions = PositionsTotal();
   for(int i = 0; i < total_positions; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != sym)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      total_volume += PositionGetDouble(POSITION_VOLUME);
   }
   return total_volume;
}

void EvaluateCycle(string reason)
{
   UpdateConfig();
   SetTargetsFromInputs(g_state);
   UpdateDrawdown(g_state);

   if(KillSwitchActive(g_state, g_cfg))
   {
      LogMessage("Kill switch active: REVIEW_ONLY mode");
      SavePortfolioState(g_state);
      return;
   }

   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   bool account_mismatch = (g_state.account_login != login) || (g_state.account_server != server);

   bool portfolio_incomplete = false;
   int open_positions = 0;
   int missing_positions = 0;
   int total_targets = ArraySize(g_state.targets);
   for(int i=0; i<total_targets; i++)
   {
      string symbol = g_state.targets[i].symbol;
      double vol = PortfolioPositionVolumeByMagic(symbol, g_cfg.magic);
      if(vol <= 0.0)
      {
         portfolio_incomplete = true;
         missing_positions++;
      }
      else
      {
         open_positions++;
      }
   }
   LogMessage(StringFormat("Phase select: incomplete=%d open_positions=%d missing=%d",
      portfolio_incomplete ? 1 : 0, open_positions, missing_positions));

   bool need_bootstrap = portfolio_incomplete || account_mismatch;

   if(need_bootstrap)
   {
      g_state.account_login = login;
      g_state.account_server = server;
      ExecuteBootstrap(trade, g_state, g_cfg);
      SavePortfolioState(g_state);
      return;
   }

   if(RebalanceDue(g_state, g_cfg))
   {
      ExecuteRebalance(trade, g_state, g_cfg);
      SavePortfolioState(g_state);
      return;
   }

   LogMessage("Rebalance check: no action");
   SavePortfolioState(g_state);
}

int OnInit()
{
   LogMessage("EA init");
   UpdateConfig();
   bool loaded = LoadPortfolioState(InpPortfolioId, g_state);
   if(!loaded)
   {
      g_state.schema_version = 1;
      g_state.portfolio_id = InpPortfolioId;
      g_state.run_id = GenerateRunId();
      g_state.account_login = 0;
      g_state.account_server = "";
      g_state.last_bootstrap_ts = 0;
      g_state.last_rebalance_ts = 0;
      g_state.equity_high = AccountInfoDouble(ACCOUNT_EQUITY);
      g_state.last_dd_pct = 0.0;
      LogMessage("State initialized from defaults");
   }
   if(g_state.run_id == "")
      g_state.run_id = GenerateRunId();
   g_state.portfolio_id = InpPortfolioId;
   SetTargetsFromInputs(g_state);
   SavePortfolioState(g_state);

   EventSetTimer(3600);
   EvaluateCycle("init");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SavePortfolioState(g_state);
   LogMessage("EA deinit");
}

void OnTimer()
{
   EvaluateCycle("timer");
}
