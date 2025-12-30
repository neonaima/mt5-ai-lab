#ifndef PORTFOLIO_UTILS_MQH
#define PORTFOLIO_UTILS_MQH

string PortfolioLogPath()
{
   return "portfolio_bridge/logs/portfolio_log.txt";
}

string BridgeOutPath(string filename)
{
   return "portfolio_bridge/out/" + filename;
}

string StateFilePath(string portfolio_id)
{
   return "portfolio_bridge/state/" + portfolio_id + "_state.json";
}

string CurrentTimestamp()
{
   datetime now = TimeCurrent();
   return TimeToString(now, TIME_DATE|TIME_SECONDS);
}

void LogMessage(string message)
{
   string line = CurrentTimestamp() + " | " + message;
   Print(line);
   int handle = FileOpen(PortfolioLogPath(), FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, line);
      FileClose(handle);
   }
}

string GenerateRunId()
{
   datetime now = TimeCurrent();
   string stamp = TimeToString(now, TIME_DATE|TIME_SECONDS);
   stamp = StringReplace(stamp, ".", "");
   stamp = StringReplace(stamp, ":", "");
   stamp = StringReplace(stamp, " ", "_");
   return stamp;
}

string BuildAccountSignature()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   return IntegerToString((int)login) + "@" + server;
}

bool EnsureSymbolReady(string symbol)
{
   if(!SymbolSelect(symbol, true))
   {
      LogMessage("SymbolSelect failed for " + symbol);
      return false;
   }
   if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_ALLOWED))
   {
      LogMessage("Trading disabled for symbol " + symbol);
      return false;
   }
   return true;
}

double NormalizeVolume(string symbol, double volume_raw)
{
   double min_vol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(volume_raw <= 0.0)
      return 0.0;
   if(min_vol > 0.0 && volume_raw < min_vol)
      return 0.0;
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = min_vol;
   if(step <= 0.0)
      return 0.0;
   double volume = MathFloor(volume_raw / step) * step;
   volume = MathMax(min_vol, volume);
   volume = MathMin(max_vol, volume);
   long digits_value = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   int digits = (int)digits_value;
   return NormalizeDouble(volume, digits);
}

double SymbolValuePerLot(string symbol, double price)
{
   double contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   return contract_size * price;
}

double SymbolSpreadPoints(string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;
   return (ask - bid) / point;
}

#endif
