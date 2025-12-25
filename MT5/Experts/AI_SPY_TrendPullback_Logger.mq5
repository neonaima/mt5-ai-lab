#property strict
#property description "SPY H4 Trend Pullback logger (step1, no trading)"

input string InpSymbol = ""; // Empty uses current chart symbol
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_H4;
input int InpFastEMA = 20;
input int InpSlowEMA = 50;
input int InpRSIPeriod = 14;
input int InpATRPeriod = 14;
input int InpADXPeriod = 14;
input double InpADXMin = 18.0;
input double InpATRMinPct = 0.006;
input double InpRSILongMin = 40.0;
input double InpRSILongMax = 50.0;
input double InpRSIShortMin = 50.0;
input double InpRSIShortMax = 60.0;
input double InpPullbackMaxDistATR = 0.35;
input bool InpLogToFile = true;
input string InpFileName = "mt5_spy_signals.jsonl";

int g_ema_fast_handle = INVALID_HANDLE;
int g_ema_slow_handle = INVALID_HANDLE;
int g_rsi_handle = INVALID_HANDLE;
int g_atr_handle = INVALID_HANDLE;
int g_adx_handle = INVALID_HANDLE;

string ResolveSymbol()
{
   if(StringLen(InpSymbol) == 0)
      return _Symbol;
   return InpSymbol;
}

int OnInit()
{
   string symbol = ResolveSymbol();
   ENUM_TIMEFRAMES tf = InpTimeframe;

   g_ema_fast_handle = iMA(symbol, tf, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_ema_slow_handle = iMA(symbol, tf, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_rsi_handle = iRSI(symbol, tf, InpRSIPeriod, PRICE_CLOSE);
   g_atr_handle = iATR(symbol, tf, InpATRPeriod);
   g_adx_handle = iADX(symbol, tf, InpADXPeriod);

   if(g_ema_fast_handle == INVALID_HANDLE || g_ema_slow_handle == INVALID_HANDLE ||
      g_rsi_handle == INVALID_HANDLE || g_atr_handle == INVALID_HANDLE ||
      g_adx_handle == INVALID_HANDLE)
   {
      Print("AI_SPY_TP_LOG | failed to create indicator handles");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_ema_fast_handle != INVALID_HANDLE)
      IndicatorRelease(g_ema_fast_handle);
   if(g_ema_slow_handle != INVALID_HANDLE)
      IndicatorRelease(g_ema_slow_handle);
   if(g_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(g_rsi_handle);
   if(g_atr_handle != INVALID_HANDLE)
      IndicatorRelease(g_atr_handle);
   if(g_adx_handle != INVALID_HANDLE)
      IndicatorRelease(g_adx_handle);
}

bool CopySingleValue(const int handle, const int buffer, const int shift, double &value)
{
   double data[];
   int copied = CopyBuffer(handle, buffer, shift, 1, data);
   if(copied != 1)
      return false;
   value = data[0];
   return true;
}

void LogToFile(const string ts, const string symbol, const string timeframe,
               const double close_price, const double ema_fast, const double ema_slow,
               const double rsi, const double atr, const double adx,
               const bool regime_ok, const string bias, const string decision)
{
   if(!InpLogToFile)
      return;

   int file_handle = FileOpen(InpFileName, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_WRITE);
   if(file_handle == INVALID_HANDLE)
   {
      PrintFormat("AI_SPY_TP_LOG | file open failed (%d)", GetLastError());
      return;
   }

   FileSeek(file_handle, 0, SEEK_END);
   string json = StringFormat("{\"ts\":\"%s\",\"symbol\":\"%s\",\"timeframe\":\"%s\",\"close\":%s,\"ema20\":%s,\"ema50\":%s,\"rsi\":%s,\"atr\":%s,\"adx\":%s,\"regime_ok\":%s,\"bias\":\"%s\",\"decision\":\"%s\"}",
                              ts,
                              symbol,
                              timeframe,
                              DoubleToString(close_price, 6),
                              DoubleToString(ema_fast, 6),
                              DoubleToString(ema_slow, 6),
                              DoubleToString(rsi, 6),
                              DoubleToString(atr, 6),
                              DoubleToString(adx, 6),
                              regime_ok ? "true" : "false",
                              bias,
                              decision);
   FileWrite(file_handle, json);
   FileClose(file_handle);
}

void OnTick()
{
   string symbol = ResolveSymbol();
   ENUM_TIMEFRAMES tf = InpTimeframe;

   datetime bar_time = iTime(symbol, tf, 1);
   if(bar_time <= 0)
      return;

   static datetime last_bar_time = 0;
   if(bar_time == last_bar_time)
      return;
   last_bar_time = bar_time;

   double ema_fast = 0.0;
   double ema_slow = 0.0;
   double rsi = 0.0;
   double atr = 0.0;
   double adx = 0.0;

   if(!CopySingleValue(g_ema_fast_handle, 0, 1, ema_fast) ||
      !CopySingleValue(g_ema_slow_handle, 0, 1, ema_slow) ||
      !CopySingleValue(g_rsi_handle, 0, 1, rsi) ||
      !CopySingleValue(g_atr_handle, 0, 1, atr) ||
      !CopySingleValue(g_adx_handle, 0, 1, adx))
   {
      PrintFormat("AI_SPY_TP_LOG | CopyBuffer failed (%d)", GetLastError());
      return;
   }

   double close_price = iClose(symbol, tf, 1);
   if(close_price == 0.0)
   {
      Print("AI_SPY_TP_LOG | close price unavailable");
      return;
   }

   bool regime_ok = (adx >= InpADXMin) && (atr / close_price >= InpATRMinPct);
   string bias = "NONE";
   string decision = "NO_SETUP";

   if(!regime_ok)
   {
      decision = "REGIME_BLOCK";
   }
   else
   {
      bool long_bias = (ema_fast > ema_slow) && (close_price > ema_fast);
      bool short_bias = (ema_fast < ema_slow) && (close_price < ema_fast);

      if(long_bias)
         bias = "LONG";
      else if(short_bias)
         bias = "SHORT";
      else
         bias = "NONE";

      if(bias == "NONE")
      {
         decision = "BIAS_BLOCK";
      }
      else
      {
         double dist = MathAbs(close_price - ema_fast);
         bool pullback_ok = (dist <= InpPullbackMaxDistATR * atr);

         if(bias == "LONG")
         {
            if(rsi >= InpRSILongMin && rsi <= InpRSILongMax && pullback_ok)
               decision = "LONG_SETUP";
         }
         else if(bias == "SHORT")
         {
            if(rsi >= InpRSIShortMin && rsi <= InpRSIShortMax && pullback_ok)
               decision = "SHORT_SETUP";
         }
      }
   }

   string tf_label = EnumToString(tf);
   if(StringFind(tf_label, "PERIOD_") == 0)
      tf_label = StringSubstr(tf_label, 7);

   string ts = TimeToString(bar_time, TIME_DATE | TIME_MINUTES);

   PrintFormat("AI_SPY_TP_LOG | %s | %s %s | close=%s ema20=%s ema50=%s rsi=%s atr=%s adx=%s | decision=%s",
               ts,
               symbol,
               tf_label,
               DoubleToString(close_price, 6),
               DoubleToString(ema_fast, 6),
               DoubleToString(ema_slow, 6),
               DoubleToString(rsi, 6),
               DoubleToString(atr, 6),
               DoubleToString(adx, 6),
               decision);

   LogToFile(ts, symbol, tf_label, close_price, ema_fast, ema_slow, rsi, atr, adx, regime_ok, bias, decision);
}
