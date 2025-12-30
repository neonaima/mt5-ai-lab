#ifndef PORTFOLIO_BRIDGE_MQH
#define PORTFOLIO_BRIDGE_MQH

#include "PortfolioUtils.mqh"
#include "PortfolioState.mqh"

void WriteRebalanceProposal(const PortfolioState &state, string reason)
{
   string filename = state.portfolio_id + "_proposal.json";
   int handle = FileOpen(BridgeOutPath(filename), FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      LogMessage("Failed to write rebalance proposal");
      return;
   }
   FileWrite(handle, "{");
   FileWrite(handle, " \"portfolio_id\": \"", state.portfolio_id, "\",");
   FileWrite(handle, " \"run_id\": \"", state.run_id, "\",");
   FileWrite(handle, " \"timestamp\": \"", CurrentTimestamp(), "\",");
   FileWrite(handle, " \"reason\": \"", reason, "\",");
   FileWrite(handle, " \"targets\": [");
   int total = ArraySize(state.targets);
   for(int i=0; i<total; i++)
   {
      FileWrite(handle, "{ \"symbol\": \"", state.targets[i].symbol, "\", \"weight\": ", DoubleToString(state.targets[i].weight, 4), " }");
      if(i < total - 1)
         FileWrite(handle, ",");
   }
   FileWrite(handle, "] }");
   FileClose(handle);
}

#endif
