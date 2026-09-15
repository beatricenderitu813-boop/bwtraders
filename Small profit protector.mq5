//+------------------------------------------------------------------+
//| ULTRA FAST 5&8 + BUTTON - CLEAN NO ERRORS |
//+------------------------------------------------------------------+
#property strict

input double Lots = 0.01;
input int FastEMA = 5;
input int SlowEMA = 8;
input int TargetPoints = 80;
input int ReEnterDelaySeconds = 5;

int ema_fast, ema_slow;
datetime lastCloseTime=0;
bool TradingEnabled=true;

//+------------------------------------------------------------------+
int OnInit()
  {
   ema_fast = iMA(_Symbol, PERIOD_M5, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   ema_slow = iMA(_Symbol, PERIOD_M5, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   ObjectCreate(0,"BTN_TRADE",OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XSIZE,130);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YSIZE,30);
   ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING");
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_COLOR,clrBlack);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_FONTSIZE,10);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ema_fast);
   IndicatorRelease(ema_slow);
   ObjectDelete(0,"BTN_TRADE");
   Comment("");
  }
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_CLICK && sparam=="BTN_TRADE")
     {
      TradingEnabled=!TradingEnabled;
      if(TradingEnabled)
        {
         ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING");
         ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);
        }
      else
        {
         ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"START TRADING");
         ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrRed);
        }
      ChartRedraw();
     }
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   double f[],s[];
   if(CopyBuffer(ema_fast,0,0,3,f)!=3) return;
   if(CopyBuffer(ema_slow,0,0,3,s)!=3) return;
   ArraySetAsSeries(f,true);
   ArraySetAsSeries(s,true);

   double dist=MathAbs(f[1]-s[1])/_Point;
   double pts=GetPts();
   double money=GetMoney();
   int cnt=CountTrades();
   string status=TradingEnabled? "ON" : "OFF";
   string trend=f[1]>s[1]? "UP BUY" : "DOWN SELL";
   string next=(TimeCurrent()-lastCloseTime >= ReEnterDelaySeconds)? "READY" : IntegerToString(ReEnterDelaySeconds-(int)(TimeCurrent()-lastCloseTime))+"s";

   Comment("=== ULTRA FAST 5&8 ===\n",
           "Status: ",status," | Trend: ",trend,"\n",
           "Dist: ",DoubleToString(dist,1)," pts\n",
           "Trades: ",cnt,"/2 | Profit: ",DoubleToString(pts,1)," pts $",DoubleToString(money,2),"\n",
           "Target: 80 pts (~$1.60)\n",
           "Next: ",next);

   if(cnt>=1 && pts>=TargetPoints)
     {
      CloseAll();
      lastCloseTime=TimeCurrent();
      return;
     }

   if(!TradingEnabled) return;
   if(cnt>=2) return;
   if(TimeCurrent()-lastCloseTime < ReEnterDelaySeconds) return;

   if(f[1]>s[1]) OpenTwo(ORDER_TYPE_BUY);
   else if(f[1]<s[1]) OpenTwo(ORDER_TYPE_SELL);
  }
//+------------------------------------------------------------------+
void OpenTwo(ENUM_ORDER_TYPE type)
  {
   for(int i=0;i<2;i++)
     {
      MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
      double price=(type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
      req.action=TRADE_ACTION_DEAL
