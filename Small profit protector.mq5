//+------------------------------------------------------------------+
//| ULTRA FAST 5&8 + BUTTON - 0 ERRORS 0 WARNINGS |
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
      req.action=TRADE_ACTION_DEAL;
      req.symbol=_Symbol;
      req.volume=Lots;
      req.type=type;
      req.price=price;
      req.deviation=30;
      req.magic=1111;
      if(!OrderSend(req,res))
         Print("OrderSend failed: ",GetLastError());
      Sleep(150);
     }
  }
//+------------------------------------------------------------------+
int CountTrades()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) c++;
     }
   return(c);
  }
//+------------------------------------------------------------------+
double GetPts()
  {
   double tot=0; int cnt=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i); if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double o=PositionGetDouble(POSITION_PRICE_OPEN);
      double cu=PositionGetDouble(POSITION_PRICE_CURRENT);
      long ty=PositionGetInteger(POSITION_TYPE);
      if(ty==POSITION_TYPE_BUY) tot+=(cu-o)/_Point;
      else tot+=(o-cu)/_Point;
      cnt++;
     }
   return(cnt>0?tot/cnt:0);
  }
//+------------------------------------------------------------------+
double GetMoney()
  {
   double p=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) p+=PositionGetDouble(POSITION_PROFIT);
     }
   return(p);
  }
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i); if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
      req.action=TRADE_ACTION_DEAL;
      req.symbol=_Symbol;
      req.volume=PositionGetDouble(POSITION_VOLUME);
      req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE));
      req.price=(req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
      req.deviation=30;
      req.position=t;
      if(!OrderSend(req,res))
         Print("Close failed: ",GetLastError());
     }
  }
//+------------------------------------------------------------------+
