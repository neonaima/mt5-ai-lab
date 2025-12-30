#ifndef PORTFOLIO_STATE_MQH
#define PORTFOLIO_STATE_MQH

#include "PortfolioUtils.mqh"

struct PortfolioTarget
{
   string symbol;
   double weight;
};

struct PortfolioState
{
   int schema_version;
   string portfolio_id;
   string run_id;
   long account_login;
   string account_server;
   datetime last_bootstrap_ts;
   datetime last_rebalance_ts;
   double equity_high;
   double last_dd_pct;
   PortfolioTarget targets[];
};

string JsonExtractString(string json, string key)
{
   string needle = "\"" + key + "\"";
   int pos = StringFind(json, needle);
   if(pos < 0)
      return "";
   pos = StringFind(json, ":", pos);
   if(pos < 0)
      return "";
   pos = StringFind(json, "\"", pos);
   if(pos < 0)
      return "";
   int end = StringFind(json, "\"", pos + 1);
   if(end < 0)
      return "";
   return StringSubstr(json, pos + 1, end - pos - 1);
}

string TrimWhitespace(string value)
{
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
}

long JsonExtractLong(string json, string key)
{
   string needle = "\"" + key + "\"";
   int pos = StringFind(json, needle);
   if(pos < 0)
      return 0;
   pos = StringFind(json, ":", pos);
   if(pos < 0)
      return 0;
   int end = StringFind(json, ",", pos);
   if(end < 0)
      end = StringFind(json, "}", pos);
   if(end < 0)
      end = StringLen(json);
   string chunk = StringSubstr(json, pos + 1, end - pos - 1);
   return (long)StringToInteger(TrimWhitespace(chunk));
}

double JsonExtractDouble(string json, string key)
{
   string needle = "\"" + key + "\"";
   int pos = StringFind(json, needle);
   if(pos < 0)
      return 0.0;
   pos = StringFind(json, ":", pos);
   if(pos < 0)
      return 0.0;
   int end = StringFind(json, ",", pos);
   if(end < 0)
      end = StringFind(json, "}", pos);
   if(end < 0)
      end = StringLen(json);
   string chunk = StringSubstr(json, pos + 1, end - pos - 1);
   return StringToDouble(TrimWhitespace(chunk));
}

bool LoadPortfolioState(string portfolio_id, PortfolioState &state)
{
   string path = StateFilePath(portfolio_id);
   int handle = FileOpen(path, FILE_READ|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
      return false;
   string json = "";
   while(!FileIsEnding(handle))
   {
      json += FileReadString(handle);
   }
   FileClose(handle);
   if(StringLen(json) == 0)
      return false;
   state.schema_version = (int)JsonExtractLong(json, "schema_version");
   state.portfolio_id = JsonExtractString(json, "portfolio_id");
   state.run_id = JsonExtractString(json, "run_id");
   state.account_login = JsonExtractLong(json, "login");
   state.account_server = JsonExtractString(json, "server");
   state.last_bootstrap_ts = (datetime)JsonExtractLong(json, "last_bootstrap_ts");
   state.last_rebalance_ts = (datetime)JsonExtractLong(json, "last_rebalance_ts");
   state.equity_high = JsonExtractDouble(json, "equity_high");
   state.last_dd_pct = JsonExtractDouble(json, "last_dd_pct");
   return true;
}

void SavePortfolioState(const PortfolioState &state)
{
   string path = StateFilePath(state.portfolio_id);
   int handle = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      LogMessage("Failed to open state file for write: " + path);
      return;
   }
   FileWrite(handle, "{");
   FileWrite(handle, " \"schema_version\": ", state.schema_version, ",");
   FileWrite(handle, " \"portfolio_id\": \"", state.portfolio_id, "\",");
   FileWrite(handle, " \"run_id\": \"", state.run_id, "\",");
   FileWrite(handle, " \"account_signature\": { \"login\": ", state.account_login, ", \"server\": \"", state.account_server, "\" },");
   FileWrite(handle, " \"last_bootstrap_ts\": ", (long)state.last_bootstrap_ts, ",");
   FileWrite(handle, " \"last_rebalance_ts\": ", (long)state.last_rebalance_ts, ",");
   FileWrite(handle, " \"equity_high\": ", DoubleToString(state.equity_high, 2), ",");
   FileWrite(handle, " \"last_dd_pct\": ", DoubleToString(state.last_dd_pct, 5), ",");
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
