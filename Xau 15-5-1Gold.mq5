#property strict
#property version   "1.10 GOLD EDITION"

input double LotSize = 0.02;        // Gold: start 0.01-0.03 only
input double SL_Dollars = 3.5;      // Stop Loss in $ - Gold needs bigger
input double TP_Dollars = 7.0;      // Take Profit in $ - 1:2 RR
input int EMA_Period = 50;
input int MaxSpreadPoints = 500;    // 500 = $5.00 spread max

bool isActive = false;
string btnName = "GOLD_BTN";

//+------------------------------------------------------------------+
int OnInit(){
   ObjectCreate(0, btnName, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, 20);
   ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, btnName, OBJPROP_XSIZE, 140);
   ObjectSetInteger(0, btnName, OBJPROP_YSIZE, 45);
   ObjectSetString(0, btnName, OBJPROP_TEXT, "▶ START GOLD");
   ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrGold);
   ObjectSetInteger(0, btnName, OBJPROP_COLOR, clrBlack);
   ObjectSetInteger(0, btnName, OBJPROP_FONTSIZE, 10);
   Print("Gold Scalper Loaded - Ready for NY Session");
   return(INIT_SUCCEEDED);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam){
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==btnName){
      isActive = !isActive;
      ObjectSetString(0, btnName, OBJPROP_TEXT, isActive ? "■ STOP GOLD" : "▶ START GOLD");
      ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, isActive ? clrTomato : clrGold);
      ChartRedraw();
   }
}

void OnTick(){
   if(!isActive) return;
   if(PositionsTotal()>=1) return;

   // 1. SPREAD FILTER - Critical for Gold
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints) return;

   double ema15 = iMA(_Symbol, PERIOD_M15, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   double ema5  = iMA(_Symbol, PERIOD_M5, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   double close15 = iClose(_Symbol, PERIOD_M15, 1);
   double close5  = iClose(_Symbol, PERIOD_M5, 1);
   double rsi1 = iRSI(_Symbol, PERIOD_M1, 14, PRICE_CLOSE);

   // 15M TREND
   bool uptrend = close15 > ema15;
   bool downtrend = close15 < ema15;

   // 5M PULLBACK
   bool pullbackToSupport = MathAbs(close5 - ema5) < 2.0; // within $2 of EMA
   bool rsiBounceBuy = rsi1 > 32 && rsi1 < 58 && rsi1 > iRSI(_Symbol, PERIOD_M1, 14, PRICE_CLOSE);
   
   // 1M ENGULFING CANDLES
   double o1 = iOpen(_Symbol, PERIOD_M1, 1); double c1 = iClose(_Symbol, PERIOD_M1, 1);
   double o2 = iOpen(_Symbol, PERIOD_M1, 2); double c2 = iClose(_Symbol, PERIOD_M1, 2);
   bool bullEngulf = (c1 > o1) && (c2 < o2) && (c1 > o2) && (o1 < c2);
   bool bearEngulf = (c1 < o1) && (c2 > o2) && (c1 < o2) && (o1 > c2);
   bool rsiBuySignal = rsi1 > 35 && rsi1 < 60;
   bool rsiSellSignal = rsi1 < 65 && rsi1 > 40;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // BUY SETUP - As in drawing
   if(uptrend && pullbackToSupport && bullEngulf && rsiBuySignal){
      double sl = ask - SL_Dollars;
      double tp = ask + TP_Dollars;
      DrawLevels(ask, sl, tp, true);
      ExecuteTrade(ORDER_TYPE_BUY, ask, sl, tp);
   }
   // SELL SETUP
   if(downtrend && pullbackToSupport && bearEngulf && rsiSellSignal){
      double sl = bid + SL_Dollars;
      double tp = bid - TP_Dollars;
      DrawLevels(bid, sl, tp, false);
      ExecuteTrade(ORDER_TYPE_SELL, bid, sl, tp);
   }
}

void DrawLevels(double entry, double sl, double tp, bool isBuy){
   ObjectDelete(0, "G_ENTRY"); ObjectDelete(0, "G_SL"); ObjectDelete(0, "G_TP");
   ObjectCreate(0, "G_ENTRY", OBJ_HLINE, 0, 0, entry); ObjectSetInteger(0, "G_ENTRY", OBJPROP_COLOR, isBuy?clrLime:clrOrange); ObjectSetInteger(0,"G_ENTRY",OBJPROP_WIDTH,2);
   ObjectCreate(0, "G_SL", OBJ_HLINE, 0, 0, sl); ObjectSetInteger(0, "G_SL", OBJPROP_COLOR, clrRed); ObjectSetInteger(0,"G_SL",OBJPROP_STYLE,STYLE_DASH);
   ObjectCreate(0, "G_TP", OBJ_HLINE, 0, 0, tp); ObjectSetInteger(0, "G_TP", OBJPROP_COLOR, clrAqua); ObjectSetInteger(0,"G_TP",OBJPROP_STYLE,STYLE_DASH);
}

void ExecuteTrade(ENUM_ORDER_TYPE type, double price, double sl, double tp){
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
   req.action = TRADE_ACTION_DEAL; req.symbol = _Symbol; req.volume = LotSize;
   req.type = type; req.price = price; req.sl = sl; req.tp = tp;
   req.deviation = 30; req.magic = 1515; req.type_filling = ORDER_FILLING_IOC;
   if(!OrderSend(req, res)) Print("Trade Failed: ", res.retcode);
   else Print("GOLD TRADE EXECUTED: ", EnumToString(type), " @ ", price);
}

void OnDeinit(const int reason){ ObjectDelete(0, btnName); ObjectDelete(0,"G_ENTRY"); ObjectDelete(0,"G_SL"); ObjectDelete(0,"G_TP"); }
