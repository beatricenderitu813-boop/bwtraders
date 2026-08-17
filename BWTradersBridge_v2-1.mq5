//+------------------------------------------------------------------+
//| BWTraders MT5 Bridge                                             |
//| BWTraders <-> MT5 automatic execution bridge                    |
//| DEMO execution enabled; LIVE requires explicit approval         |
//+------------------------------------------------------------------+
#property strict
#property version   "2.0"

#include <Trade/Trade.mqh>

CTrade trade;

input string ConnectorBaseURL =
   "https://bwtraders-mt5-connector.onrender.com";

input string BWTradersAPIKey = "";

input string Symbol1 = "EURUSD";
input string Symbol2 = "XAUUSD";

input int SendIntervalSeconds = 10;
input double DefaultVolume = 0.01;
input ulong MagicNumber = 26081701;

// Safety switch. Keep FALSE until complete demo testing is finished.
input bool EnableLiveTrading = false;

datetime lastBarH1_1 = 0;
datetime lastBarM15_1 = 0;
datetime lastBarM5_1 = 0;
datetime lastBarH1_2 = 0;
datetime lastBarM15_2 = 0;
datetime lastBarM5_2 = 0;


//+------------------------------------------------------------------+
//| URLs                                                             |
//+------------------------------------------------------------------+
string MarketURL()
{
   return ConnectorBaseURL + "/mt5/market";
}

string CommandURL()
{
   return ConnectorBaseURL + "/mt5/command";
}

string StatusURL()
{
   return ConnectorBaseURL + "/mt5/status";
}

string TradeResultURL()
{
   return ConnectorBaseURL + "/mt5/trade-result";
}


//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string JsonNumber(double value)
{
   return DoubleToString(value, 8);
}

string Headers()
{
   return
      "Content-Type: application/json\r\n"
      "X-API-Key: " + BWTradersAPIKey + "\r\n";
}

string GetJsonString(string json, string key)
{
   string needle = "\"" + key + "\":\"";
   int p = StringFind(json, needle);

   if(p < 0)
      return "";

   p += StringLen(needle);

   int end = StringFind(json, "\"", p);

   if(end < 0)
      return "";

   return StringSubstr(json, p, end - p);
}

double GetJsonDouble(string json, string key, double fallback=0.0)
{
   string needle = "\"" + key + "\":";
   int p = StringFind(json, needle);

   if(p < 0)
      return fallback;

   p += StringLen(needle);

   while(p < StringLen(json))
   {
      ushort c = StringGetCharacter(json, p);

      if(c == ' ' || c == '\t')
         p++;
      else
         break;
   }

   int end = p;

   while(end < StringLen(json))
   {
      ushort c = StringGetCharacter(json, end);

      if(c == ',' || c == '}' || c == ' ' || c == '\r' || c == '\n')
         break;

      end++;
   }

   string value = StringSubstr(json, p, end - p);

   if(value == "")
      return fallback;

   return StringToDouble(value);
}

bool HttpPost(string url, string json, string &responseText)
{
   char post[];
   char result[];
   string resultHeaders;

   StringToCharArray(json, post, 0, StringLen(json));

   ResetLastError();

   int response = WebRequest(
      "POST",
      url,
      Headers(),
      10000,
      post,
      result,
      resultHeaders
   );

   if(response == -1)
   {
      Print("BWTraders POST error. URL=", url,
            " Error=", GetLastError());
      return false;
   }

   responseText = CharArrayToString(result);

   if(response < 200 || response >= 300)
   {
      Print("BWTraders POST HTTP ", response,
            ": ", responseText);
      return false;
   }

   return true;
}

bool HttpGet(string url, string &responseText)
{
   char data[];
   char result[];
   string resultHeaders;

   ResetLastError();

   int response = WebRequest(
      "GET",
      url,
      Headers(),
      10000,
      data,
      0,
      result,
      resultHeaders
   );

   if(response == -1)
   {
      Print("BWTraders GET error. URL=", url,
            " Error=", GetLastError());
      return false;
   }

   responseText = CharArrayToString(result);

   if(response < 200 || response >= 300)
   {
      Print("BWTraders GET HTTP ", response,
            ": ", responseText);
      return false;
   }

   return true;
}


//+------------------------------------------------------------------+
//| Market data                                                      |
//+------------------------------------------------------------------+
string TimeframeName(ENUM_TIMEFRAMES timeframe)
{
   if(timeframe == PERIOD_H1)
      return "H1";

   if(timeframe == PERIOD_M15)
      return "M15";

   return "M5";
}

bool SendBar(string symbol, ENUM_TIMEFRAMES timeframe, MqlRates &bar)
{
   string json =
      "{"
      "\"symbol\":\"" + symbol + "\","
      "\"timeframe\":\"" + TimeframeName(timeframe) + "\","
      "\"open\":" + JsonNumber(bar.open) + ","
      "\"high\":" + JsonNumber(bar.high) + ","
      "\"low\":" + JsonNumber(bar.low) + ","
      "\"close\":" + JsonNumber(bar.close) + ","
      "\"timestamp\":\"" +
      TimeToString(bar.time, TIME_DATE|TIME_SECONDS) +
      "\""
      "}";

   string response;

   return HttpPost(MarketURL(), json, response);
}

bool SendHistory(string symbol,
                 ENUM_TIMEFRAMES timeframe,
                 datetime &lastSent)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   // The backend needs enough history for EMA50/RSI14/ATR.
   // 60 closed bars gives it a safe starting window.
   int copied = CopyRates(symbol, timeframe, 1, 60, rates);

   if(copied < 20)
   {
      Print("Not enough history for ", symbol, " ",
            TimeframeName(timeframe),
            ". Bars=", copied);
      return false;
   }

   bool ok = true;

   // Send oldest -> newest so the backend receives chronological data.
   for(int i = copied - 1; i >= 0; i--)
   {
      if(!SendBar(symbol, timeframe, rates[i]))
      {
         ok = false;
         break;
      }
   }

   if(ok)
      lastSent = rates[0].time;

   return ok;
}

bool SendNewBar(string symbol,
                ENUM_TIMEFRAMES timeframe,
                datetime &lastSent)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(symbol, timeframe, 1, 1, rates);

   if(copied < 1)
      return false;

   if(rates[0].time == lastSent)
      return true;

   if(SendBar(symbol, timeframe, rates[0]))
   {
      lastSent = rates[0].time;
      return true;
   }

   return false;
}

void SendSymbolData(string symbol,
                    datetime &lastH1,
                    datetime &lastM15,
                    datetime &lastM5)
{
   SendNewBar(symbol, PERIOD_H1, lastH1);
   SendNewBar(symbol, PERIOD_M15, lastM15);
   SendNewBar(symbol, PERIOD_M5, lastM5);
}


//+------------------------------------------------------------------+
//| MT5 account status                                               |
//+------------------------------------------------------------------+
void SendMT5Status()
{
   string json =
      "{"
      "\"connected\":true,"
      "\"account\":{"
      "\"login\":" +
      IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + ","
      "\"server\":\"" +
      AccountInfoString(ACCOUNT_SERVER) + "\","
      "\"currency\":\"" +
      AccountInfoString(ACCOUNT_CURRENCY) + "\","
      "\"balance\":" +
      JsonNumber(AccountInfoDouble(ACCOUNT_BALANCE)) + ","
      "\"equity\":" +
      JsonNumber(AccountInfoDouble(ACCOUNT_EQUITY)) + ","
      "\"margin\":" +
      JsonNumber(AccountInfoDouble(ACCOUNT_MARGIN)) + ","
      "\"free_margin\":" +
      JsonNumber(AccountInfoDouble(ACCOUNT_MARGIN_FREE)) +
      "}"
      "}";

   string response;
   HttpPost(StatusURL(), json, response);
}


//+------------------------------------------------------------------+
//| Trading helpers                                                  |
//+------------------------------------------------------------------+
int VolumeDigits(string symbol)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(step >= 1.0) return 0;
   if(step >= 0.1) return 1;
   if(step >= 0.01) return 2;

   return 3;
}

double NormalizeVolume(string symbol, double volume)
{
   double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(minVol <= 0)
      minVol = 0.01;

   if(maxVol <= 0)
      maxVol = volume;

   if(step <= 0)
      step = minVol;

   volume = MathMax(minVol, MathMin(maxVol, volume));
   volume = MathFloor(volume / step) * step;

   if(volume < minVol)
      volume = minVol;

   return NormalizeDouble(volume, VolumeDigits(symbol));
}

double NormalizePrice(string symbol, double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

bool CloseAllPositions()
{
   bool allClosed = true;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);

      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);

      if(!trade.PositionClose(ticket))
      {
         Print("Emergency close failed: ",
               symbol,
               " ticket=", ticket,
               " retcode=",
               trade.ResultRetcode(),
               " ",
               trade.ResultRetcodeDescription());

         allClosed = false;
      }
      else
      {
         Print("Emergency close: ",
               symbol,
               " ticket=", ticket);
      }
   }

   return allClosed;
}

bool ExecuteOpen(string symbol,
                 string action,
                 double volume,
                 double sl,
                 double tp)
{
   if(symbol == "")
      return false;

   if(!SymbolSelect(symbol, true))
   {
      Print("Cannot select symbol ", symbol);
      return false;
   }

   long tradeMode =
      SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);

   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      Print("Trading disabled for ", symbol);
      return false;
   }

   if(volume <= 0)
      volume = DefaultVolume;

   volume = NormalizeVolume(symbol, volume);

   sl = NormalizePrice(symbol, sl);
   tp = NormalizePrice(symbol, tp);

   bool ok = false;

   if(action == "BUY")
      ok = trade.Buy(
         volume,
         symbol,
         0.0,
         sl,
         tp,
         "BWTraders"
      );

   else if(action == "SELL")
      ok = trade.Sell(
         volume,
         symbol,
         0.0,
         sl,
         tp,
         "BWTraders"
      );

   else
   {
      Print("Unsupported action: ", action);
      return false;
   }

   if(!ok)
   {
      Print(
         "BWTraders order failed. ",
         action,
         " ",
         symbol,
         " retcode=",
         trade.ResultRetcode(),
         " ",
         trade.ResultRetcodeDescription()
      );

      return false;
   }

   Print(
      "BWTraders order executed: ",
      action,
      " ",
      symbol,
      " volume=",
      DoubleToString(volume, VolumeDigits(symbol)),
      " order=",
      trade.ResultOrder()
   );

   return true;
}


//+------------------------------------------------------------------+
//| Command processing                                               |
//+------------------------------------------------------------------+
void ProcessCommand()
{
   string response;

   if(!HttpGet(CommandURL(), response))
      return;

   string command = GetJsonString(response, "command");

   if(command == "" || command == "WAIT")
      return;

   string mode = GetJsonString(response, "mode");

   // Emergency command: close all open positions.
   if(command == "CLOSE_ALL")
   {
      CloseAllPositions();
      return;
   }

   if(command != "OPEN")
   {
      Print("Unknown BWTraders command: ", command);
      return;
   }

   // LIVE is intentionally locked locally until verified.
   if(mode == "LIVE" && !EnableLiveTrading)
   {
      Print("LIVE command blocked: EnableLiveTrading=false.");
      return;
   }

   if(mode != "DEMO" && mode != "LIVE")
   {
      Print("Invalid BWTraders mode: ", mode);
      return;
   }

   bool accountDemo =
      (AccountInfoInteger(ACCOUNT_TRADE_MODE)
       == ACCOUNT_TRADE_MODE_DEMO);

   if(mode == "DEMO" && !accountDemo)
   {
      Print("DEMO command blocked: MT5 account is not demo.");
      return;
   }

   if(mode == "LIVE" && accountDemo)
   {
      Print("LIVE command blocked: MT5 account is demo.");
      return;
   }

   string symbol = GetJsonString(response, "symbol");
   string action = GetJsonString(response, "action");

   double volume =
      GetJsonDouble(response, "volume", DefaultVolume);

   double sl =
      GetJsonDouble(response, "stop_loss", 0.0);

   double tp =
      GetJsonDouble(response, "take_profit", 0.0);

   if(sl <= 0 || tp <= 0)
   {
      Print("Order blocked: invalid SL/TP.");
      return;
   }

   ExecuteOpen(
      symbol,
      action,
      volume,
      sl,
      tp
   );
}


//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("BWTraders MT5 Bridge v2.0 started.");
   Print("Automatic execution architecture enabled.");
   Print("LIVE execution switch = ",
         EnableLiveTrading ? "ON" : "OFF");

   if(!SymbolSelect(Symbol1, true))
      Print("Could not select ", Symbol1);

   if(!SymbolSelect(Symbol2, true))
      Print("Could not select ", Symbol2);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetAsyncMode(false);

   // Build the backend's initial H1/M15/M5 history.
   SendHistory(Symbol1, PERIOD_H1, lastBarH1_1);
   SendHistory(Symbol1, PERIOD_M15, lastBarM15_1);
   SendHistory(Symbol1, PERIOD_M5, lastBarM5_1);

   SendHistory(Symbol2, PERIOD_H1, lastBarH1_2);
   SendHistory(Symbol2, PERIOD_M15, lastBarM15_2);
   SendHistory(Symbol2, PERIOD_M5, lastBarM5_2);

   SendMT5Status();

   EventSetTimer(SendIntervalSeconds);

   return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   Print("BWTraders MT5 Bridge stopped.");
}


//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Send only newly closed bars after initialization.
   SendSymbolData(
      Symbol1,
      lastBarH1_1,
      lastBarM15_1,
      lastBarM5_1
   );

   SendSymbolData(
      Symbol2,
      lastBarH1_2,
      lastBarM15_2,
      lastBarM5_2
   );

   SendMT5Status();

   // Poll after market data so a new M5 confirmation can
   // produce a trade command.
   ProcessCommand();
}
