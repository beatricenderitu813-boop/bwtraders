//+------------------------------------------------------------------+
//|                 M1 Signal Scanner v1                             |
//|                 BWTraders                                        |
//|                 Signal-only M1 market scanner                     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "M1 BUY/SELL signal scanner with SL and TP."

//========================= INPUTS ===================================

input ENUM_TIMEFRAMES ScanTimeframe = PERIOD_M1;

input int FastEMA = 9;
input int SlowEMA = 21;
input int RSIPeriod = 14;
input int ATRPeriod = 14;

input double BuyRSIMin = 55.0;
input double SellRSIMax = 45.0;

input int StructureLookback = 10;

input double SL_ATR_Multiplier = 1.5;
input double RiskReward = 2.0;

input double MinimumSignalScore = 70.0;

input bool EnableAlerts = true;
input bool EnablePushNotification = false;

input color BuyColor = clrLime;
input color SellColor = clrRed;
input color NeutralColor = clrWhite;

//========================= GLOBALS ==================================

int hFastEMA = INVALID_HANDLE;
int hSlowEMA = INVALID_HANDLE;
int hRSI     = INVALID_HANDLE;
int hATR     = INVALID_HANDLE;

bool ScannerRunning = false;

datetime LastSignalTime = 0;
string LastSignal = "NONE";

double LastEntry = 0.0;
double LastSL = 0.0;
double LastTP = 0.0;
double LastScore = 0.0;

// Chart objects
string PANEL_NAME       = "M1SS_PANEL";
string STATUS_NAME      = "M1SS_STATUS";
string SIGNAL_NAME      = "M1SS_SIGNAL";
string ENTRY_LINE       = "M1SS_ENTRY";
string SL_LINE          = "M1SS_SL";
string TP_LINE          = "M1SS_TP";

string START_BUTTON = "M1SS_START";
string STOP_BUTTON  = "M1SS_STOP";

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   hFastEMA = iMA(_Symbol, ScanTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA = iMA(_Symbol, ScanTimeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI     = iRSI(_Symbol, ScanTimeframe, RSIPeriod, PRICE_CLOSE);
   hATR     = iATR(_Symbol, ScanTimeframe, ATRPeriod);

   if(hFastEMA == INVALID_HANDLE ||
      hSlowEMA == INVALID_HANDLE ||
      hRSI     == INVALID_HANDLE ||
      hATR     == INVALID_HANDLE)
   {
      Print("ERROR: Could not create indicator handles.");
      return(INIT_FAILED);
   }

   CreatePanel();
   CreateButtons();

   UpdateStatus("STOPPED - Press START");

   Print("M1 Signal Scanner initialized on ", _Symbol);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hFastEMA != INVALID_HANDLE)
      IndicatorRelease(hFastEMA);

   if(hSlowEMA != INVALID_HANDLE)
      IndicatorRelease(hSlowEMA);

   if(hRSI != INVALID_HANDLE)
      IndicatorRelease(hRSI);

   if(hATR != INVALID_HANDLE)
      IndicatorRelease(hATR);

   DeleteObjects();

   Print("M1 Signal Scanner stopped. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Tick function                                                    |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!ScannerRunning)
      return;

   ScanMarket();
}

//+------------------------------------------------------------------+
//| Create information panel                                         |
//+------------------------------------------------------------------+
void CreatePanel()
{
   if(ObjectFind(0, PANEL_NAME) < 0)
   {
      ObjectCreate(0, PANEL_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }

   ObjectSetInteger(0, PANEL_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_XSIZE, 300);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_YSIZE, 210);

   ObjectSetInteger(0, PANEL_NAME, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_BORDER_TYPE, BORDER_FLAT);

   ObjectSetInteger(0, PANEL_NAME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, PANEL_NAME, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Create START / STOP buttons                                      |
//+------------------------------------------------------------------+
void CreateButtons()
{
   CreateButton(
      START_BUTTON,
      "START",
      10,
      240,
      135,
      30
   );

   CreateButton(
      STOP_BUTTON,
      "STOP",
      155,
      240,
      135,
      30
   );
}

//+------------------------------------------------------------------+
//| Create button                                                    |
//+------------------------------------------------------------------+
void CreateButton(
   string name,
   string text,
   int x,
   int y,
   int width,
   int height
)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);

   ObjectSetString(0, name, OBJPROP_TEXT, text);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrDimGray);

   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Update status label                                               |
//+------------------------------------------------------------------+
void UpdateStatus(string text)
{
   if(ObjectFind(0, STATUS_NAME) < 0)
      ObjectCreate(0, STATUS_NAME, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, STATUS_NAME, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, STATUS_NAME, OBJPROP_XDISTANCE, 25);
   ObjectSetInteger(0, STATUS_NAME, OBJPROP_YDISTANCE, 35);

   ObjectSetString(0, STATUS_NAME, OBJPROP_TEXT, text);

   ObjectSetInteger(0, STATUS_NAME, OBJPROP_COLOR, NeutralColor);
   ObjectSetInteger(0, STATUS_NAME, OBJPROP_FONTSIZE, 10);

   ObjectSetInteger(0, STATUS_NAME, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Handle chart button clicks                                       |
//+------------------------------------------------------------------+
void OnChartEvent(
   const int id,
   const long &lparam,
   const double &dparam,
   const string &sparam
)
{
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == START_BUTTON)
   {
      ScannerRunning = true;

      UpdateStatus("SCANNING LIVE M1...");

      Print("M1 Signal Scanner STARTED.");

      ObjectSetInteger(
         0,
         START_BUTTON,
         OBJPROP_STATE,
         false
      );
   }

   if(sparam == STOP_BUTTON)
   {
      ScannerRunning = false;

      UpdateStatus("STOPPED - Press START");

      Print("M1 Signal Scanner STOPPED.");

      ObjectSetInteger(
         0,
         STOP_BUTTON,
         OBJPROP_STATE,
         false
      );
   }
}

//+------------------------------------------------------------------+
//| Main market scanner                                              |
//+------------------------------------------------------------------+
void ScanMarket()
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double fastEMA[3];
   double slowEMA[3];
   double rsi[3];
   double atr[3];

   ArraySetAsSeries(fastEMA, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hFastEMA, 0, 0, 3, fastEMA) < 3)
      return;

   if(CopyBuffer(hSlowEMA, 0, 0, 3, slowEMA) < 3)
      return;

   if(CopyBuffer(hRSI, 0, 0, 3, rsi) < 3)
      return;

   if(CopyBuffer(hATR, 0, 0, 3, atr) < 3)
      return;

   MqlRates rates[];

   ArraySetAsSeries(rates, true);

   int needed = StructureLookback + 5;

   if(CopyRates(
      _Symbol,
      ScanTimeframe,
      0,
      needed,
      rates
   ) < needed)
   {
      return;
   }

   double bid = tick.bid;
   double ask = tick.ask;

   double currentPrice = (bid + ask) / 2.0;

   double recentHigh = GetRecentHigh(
      rates,
      1,
      StructureLookback
   );

   double recentLow = GetRecentLow(
      rates,
      1,
      StructureLookback
   );

   double currentOpen = rates[0].open;
   double currentHigh = rates[0].high;
   double currentLow  = rates[0].low;

   double candleRange = currentHigh - currentLow;

   if(candleRange <= 0.0)
      return;

   double candleBody = MathAbs(
      currentPrice - currentOpen
   );

   double bodyStrength =
      candleBody / candleRange;

   double buyScore = 0.0;
   double sellScore = 0.0;

   //==============================================================
   // BUY CONDITIONS
   //==============================================================

   if(fastEMA[0] > slowEMA[0])
      buyScore += 25.0;

   if(rsi[0] >= BuyRSIMin)
      buyScore += 20.0;

   if(currentPrice > currentOpen)
      buyScore += 15.0;

   if(bodyStrength >= 0.50 &&
      currentPrice > currentOpen)
   {
      buyScore += 15.0;
   }

   if(currentPrice > recentHigh)
      buyScore += 25.0;

   //==============================================================
   // SELL CONDITIONS
   //==============================================================

   if(fastEMA[0] < slowEMA[0])
      sellScore += 25.0;

   if(rsi[0] <= SellRSIMax)
      sellScore += 20.0;

   if(currentPrice < currentOpen)
      sellScore += 15.0;

   if(bodyStrength >= 0.50 &&
      currentPrice < currentOpen)
   {
      sellScore += 15.0;
   }

   if(currentPrice < recentLow)
      sellScore += 25.0;

   //==============================================================
   // DETERMINE SIGNAL
   //==============================================================

   if(buyScore >= MinimumSignalScore &&
      buyScore > sellScore)
   {
      GenerateSignal(
         "BUY",
         buyScore,
         ask,
         atr[0],
         recentLow,
         recentHigh
      );

      return;
   }

   if(sellScore >= MinimumSignalScore &&
      sellScore > buyScore)
   {
      GenerateSignal(
         "SELL",
         sellScore,
         bid,
         atr[0],
         recentLow,
         recentHigh
      );

      return;
   }

   UpdateNeutral(
      buyScore,
      sellScore,
      rsi[0],
      currentPrice
   );
}

//+------------------------------------------------------------------+
//| Find recent high                                                 |
//+------------------------------------------------------------------+
double GetRecentHigh(
   MqlRates &rates[],
   int startIndex,
   int count
)
{
   double highest = rates[startIndex].high;

   for(int i = startIndex; i < startIndex + count; i++)
   {
      if(rates[i].high > highest)
         highest = rates[i].high;
   }

   return highest;
}

//+------------------------------------------------------------------+
//| Find recent low                                                  |
//+------------------------------------------------------------------+
double GetRecentLow(
   MqlRates &rates[],
   int startIndex,
   int count
)
{
   double lowest = rates[startIndex].low;

   for(int i = startIndex; i < startIndex + count; i++)
   {
      if(rates[i].low < lowest)
         lowest = rates[i].low;
   }

   return lowest;
}//+------------------------------------------------------------------+
//| Generate BUY or SELL signal                                      |
//+------------------------------------------------------------------+
void GenerateSignal(
   string direction,
   double score,
   double entry,
   double atr,
   double recentLow,
   double recentHigh
)
{
   if(atr <= 0.0)
      return;

   double point = SymbolInfoDouble(
      _Symbol,
      SYMBOL_POINT
   );

   int digits = (int)SymbolInfoInteger(
      _Symbol,
      SYMBOL_DIGITS
   );

   double sl = 0.0;
   double tp = 0.0;

   //==============================================================
   // BUY
   //==============================================================

   if(direction == "BUY")
   {
      double atrSL =
         entry - (atr * SL_ATR_Multiplier);

      double structureSL =
         recentLow - (atr * 0.20);

      // Use the safer/lower SL.
      sl = MathMin(
         atrSL,
         structureSL
      );

      double risk = entry - sl;

      if(risk <= 0.0)
         return;

      tp = entry + (risk * RiskReward);
   }

   //==============================================================
   // SELL
   //==============================================================

   if(direction == "SELL")
   {
      double atrSL =
         entry + (atr * SL_ATR_Multiplier);

      double structureSL =
         recentHigh + (atr * 0.20);

      // Use the safer/higher SL.
      sl = MathMax(
         atrSL,
         structureSL
      );

      double risk = sl - entry;

      if(risk <= 0.0)
         return;

      tp = entry - (risk * RiskReward);
   }

   entry = NormalizeDouble(entry, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   //==============================================================
   // Avoid repeating exactly the same signal every tick
   //==============================================================

   bool sameSignal =
      (LastSignal == direction &&
       MathAbs(LastEntry - entry) <= point * 2.0);

   if(sameSignal)
   {
      UpdateSignalDisplay(
         direction,
         score,
         entry,
         sl,
         tp
      );

      return;
   }

   LastSignalTime = TimeCurrent();
   LastSignal = direction;

   LastEntry = entry;
   LastSL = sl;
   LastTP = tp;
   LastScore = score;

   UpdateSignalDisplay(
      direction,
      score,
      entry,
      sl,
      tp
   );

   string message;

   message =
      _Symbol +
      " M1 " +
      direction +
      " SIGNAL | Score " +
      DoubleToString(score, 0) +
      "% | Entry " +
      DoubleToString(entry, digits) +
      " | SL " +
      DoubleToString(sl, digits) +
      " | TP " +
      DoubleToString(tp, digits);

   Print(message);

   if(EnableAlerts)
      Alert(message);

   if(EnablePushNotification)
      SendNotification(message);
}

//+------------------------------------------------------------------+
//| Display BUY/SELL signal                                          |
//+------------------------------------------------------------------+
void UpdateSignalDisplay(
   string direction,
   double score,
   double entry,
   double sl,
   double tp
)
{
   int digits = (int)SymbolInfoInteger(
      _Symbol,
      SYMBOL_DIGITS
   );

   string text;

   text =
      "M1 SIGNAL SCANNER\n"
      "====================\n"
      "SYMBOL: " + _Symbol + "\n"
      "TIMEFRAME: M1\n"
      "STATUS: SIGNAL FOUND\n\n"
      "DIRECTION: " + direction + "\n"
      "CONFIDENCE SCORE: " +
      DoubleToString(score, 0) + "%\n\n"
      "ENTRY: " +
      DoubleToString(entry, digits) + "\n"
      "STOP LOSS: " +
      DoubleToString(sl, digits) + "\n"
      "TAKE PROFIT: " +
      DoubleToString(tp, digits) + "\n\n"
      "RISK / REWARD: 1:" +
      DoubleToString(RiskReward, 1);

   if(ObjectFind(0, SIGNAL_NAME) < 0)
      ObjectCreate(
         0,
         SIGNAL_NAME,
         OBJ_LABEL,
         0,
         0,
         0
      );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_CORNER,
      CORNER_LEFT_UPPER
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_XDISTANCE,
      25
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_YDISTANCE,
      60
   );

   ObjectSetString(
      0,
      SIGNAL_NAME,
      OBJPROP_TEXT,
      text
   );

   if(direction == "BUY")
   {
      ObjectSetInteger(
         0,
         SIGNAL_NAME,
         OBJPROP_COLOR,
         BuyColor
      );
   }
   else
   {
      ObjectSetInteger(
         0,
         SIGNAL_NAME,
         OBJPROP_COLOR,
         SellColor
      );
   }

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_FONTSIZE,
      10
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_SELECTABLE,
      false
   );

   DrawPriceLines(
      direction,
      entry,
      sl,
      tp
   );
}

//+------------------------------------------------------------------+
//| Draw Entry / SL / TP lines                                       |
//+------------------------------------------------------------------+
void DrawPriceLines(
   string direction,
   double entry,
   double sl,
   double tp
)
{
   DrawHorizontalLine(
      ENTRY_LINE,
      entry,
      clrWhite,
      STYLE_DOT,
      1
   );

   DrawHorizontalLine(
      SL_LINE,
      sl,
      SellColor,
      STYLE_DASH,
      1
   );

   DrawHorizontalLine(
      TP_LINE,
      tp,
      BuyColor,
      STYLE_DASH,
      1
   );
}

//+------------------------------------------------------------------+
//| Draw horizontal price line                                       |
//+------------------------------------------------------------------+
void DrawHorizontalLine(
   string name,
   double price,
   color lineColor,
   ENUM_LINE_STYLE style,
   int width
)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(
         0,
         name,
         OBJ_HLINE,
         0,
         0,
         price
      );
   }
   else
   {
      ObjectSetDouble(
         0,
         name,
         OBJPROP_PRICE,
         price
      );
   }

   ObjectSetInteger(
      0,
      name,
      OBJPROP_COLOR,
      lineColor
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_STYLE,
      style
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_WIDTH,
      width
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_SELECTABLE,
      false
   );

   ObjectSetInteger(
      0,
      name,
      OBJPROP_HIDDEN,
      true
   );
}//+------------------------------------------------------------------+
//| Display neutral market condition                                 |
//+------------------------------------------------------------------+
void UpdateNeutral(
   double buyScore,
   double sellScore,
   double rsiValue,
   double price
)
{
   int digits = (int)SymbolInfoInteger(
      _Symbol,
      SYMBOL_DIGITS
   );

   string text;

   text =
      "M1 SIGNAL SCANNER\n"
      "====================\n"
      "SYMBOL: " + _Symbol + "\n"
      "TIMEFRAME: M1\n"
      "STATUS: SCANNING\n\n"
      "BUY SCORE: " +
      DoubleToString(buyScore, 0) + "%\n"
      "SELL SCORE: " +
      DoubleToString(sellScore, 0) + "%\n"
      "RSI: " +
      DoubleToString(rsiValue, 1) + "\n\n"
      "PRICE: " +
      DoubleToString(price, digits) + "\n\n"
      "WAITING FOR CONFIRMATION...";

   if(ObjectFind(0, SIGNAL_NAME) < 0)
      ObjectCreate(
         0,
         SIGNAL_NAME,
         OBJ_LABEL,
         0,
         0,
         0
      );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_CORNER,
      CORNER_LEFT_UPPER
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_XDISTANCE,
      25
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_YDISTANCE,
      60
   );

   ObjectSetString(
      0,
      SIGNAL_NAME,
      OBJPROP_TEXT,
      text
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_COLOR,
      NeutralColor
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_FONTSIZE,
      10
   );

   ObjectSetInteger(
      0,
      SIGNAL_NAME,
      OBJPROP_SELECTABLE,
      false
   );
}

//+------------------------------------------------------------------+
//| Delete chart objects                                             |
//+------------------------------------------------------------------+
void DeleteObjects()
{
   ObjectDelete(0, PANEL_NAME);
   ObjectDelete(0, STATUS_NAME);
   ObjectDelete(0, SIGNAL_NAME);

   ObjectDelete(0, ENTRY_LINE);
   ObjectDelete(0, SL_LINE);
   ObjectDelete(0, TP_LINE);

   ObjectDelete(0, START_BUTTON);
   ObjectDelete(0, STOP_BUTTON);
}

//+------------------------------------------------------------------+
//| Expert information                                               |
//+------------------------------------------------------------------+
string GetSignalDescription()
{
   if(LastSignal == "BUY")
      return "BUY setup detected.";

   if(LastSignal == "SELL")
      return "SELL setup detected.";

   return "No confirmed setup.";
}
//+------------------------------------------------------------------+
