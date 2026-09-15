//+------------------------------------------------------------------+
//| FINAL - GRAB HALF + RUNNER - ONLY CLOSE ON REVERSAL |
//| 0 ERRORS 0 WARNINGS - WITH START/STOP BUTTON |
//+------------------------------------------------------------------+
#property strict

input double Lots = 0.01;
input int FastEMA = 5;
input int SlowEMA = 13;
input int ADX_Period = 14;
input int ADX_Threshold = 25;
input int FirstTarget = 80;

int ef, es, adx_h, rsi_h;
datetime lastClose = 0;
bool trading = true;
bool halfDone = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   ef = iMA(_Symbol,PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   es = iMA(_Symbol,PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   adx_h = iADX(_Symbol,PERIOD_M5,ADX_Period);
   rsi_h = iRSI(_Symbol,PERIOD_M5,14,PRICE_CLOSE);

   ObjectCreate(0,"BTN_TRADE",OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XSIZE,130);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YSIZE,30);
   ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING");
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(ef);
   IndicatorRelease(es);
   IndicatorRelease(adx_h);
   IndicatorRelease(rsi_h);
   ObjectDelete(0,"BTN_TRADE");
   Comment("");
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &l,const double &d,const string &s)
  {
   if(id==CHARTEVENT_OBJECT_CLICK && s=="BTN_TRADE")
     {
      trading =!trading;
      if(trading)
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
   double f[], s[], adx[], rsi[];
   if(CopyBuffer(ef,0,0,3,f)!=3) return;
   if(CopyBuffer(es,0,0,3,s)!=3) return;
   if(CopyBuffer(adx_h,0,0,3,adx)!=3) return;
   if(CopyBuffer(rsi_h,0,0,3,rsi)!=3) return;
   ArraySetAsSeries(f,true);
   ArraySetAsSeries(s,true);
   ArraySetAsSeries(adx,true);
   ArraySetAsSeries(rsi,true);

   bool freshBuy = f[2]<=s[2] && f[1]>s[1];
   bool freshSell = f[2]>=s[2] && f[1]<s[1];
   bool revBuy = f[2]>=s[2] && f[1]<s[1];
   bool revSell = f[2]<=s[2] && f[1]>s[1];

   double dist = MathAbs(f[1]-s[1])/_Point;
   int cnt = CountTrades();
   double pts = GetPts();

   bool strong = adx[1] > ADX_Threshold && dist > 30;
   bool reversal = false;
   if(adx[1]<20) reversal=true;
   if(cnt>0 && IsBuy() && rsi[1]<52) reversal=true;
   if(cnt>0 &&!IsBuy() && rsi[1]>48) reversal=true;

   string mode;
   if(cnt==0) mode="WAITING CROSS";
   else if(!halfDone) mode="WAIT 80pts TO GRAB";
   else if(!reversal) mode="RUNNER - LETTING IT RUN";
   else mode="REVERSAL - WILL CLOSE";

   Comment("FINAL GRAB+RUNNER\n",
           "Trend:",(f[1]>s[1]?"BUY":"SELL"),
           " ADX:",DoubleToString(adx[1],1),
           " Dist:",DoubleToString(dist,1),"\n",
           "Trades:",cnt,"/2 Pts:",DoubleToString(pts,1),
           " Half:",(halfDone?"YES":"NO"),"\n",
           "Mode:",mode,"\n",
           "Rule: FULL CLOSE ONLY ON REVERSAL");

   if(!trading) return;

   if(cnt>=1)
     {
      if(!halfDone && pts>=FirstTarget && cnt==2)
        {
         CloseOne();
         halfDone=true;
         return;
        }
      if(halfDone)
        {
         if((IsBuy() && revBuy) || (!IsBuy() && revSell) || reversal)
           {
            CloseAll();
            halfDone=false;
            lastClose=TimeCurrent();
            return;
           }
         return;
        }
      return;
     }

   if(TimeCurrent()-lastClose < 60) return;
   if(!freshBuy &&!freshSell) return;
   if(!strong) return;
   if(cnt>=2) return;

   halfDone=false;
   if(freshBuy && rsi[1]<70 && rsi[1]>50) OpenTwo(ORDER_TYPE_BUY);
   if(freshSell && rsi[1]>30 && rsi[1]<50) OpenTwo(ORDER_TYPE_SELL);
  }

//+------------------------------------------------------------------+
void OpenTwo(ENUM_ORDER_TYPE type)
  {
   for(int i=0;i<2;i++)
     {
      if(CountTrades()>=2) return;
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      double price;
      if(type==ORDER_TYPE_BUY)
         price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      else
         price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      req.action=TRADE_ACTION_DEAL;
      req.symbol=_Symbol;
      req.volume=Lots;
      req.type=type;
      req.price=price;
      req.deviation=30;
      req.magic=20260915;
      bool ok=OrderSend(req,res);
      if(!ok) Print("OrderSend fail ",GetLastError());
     }
  }

//+------------------------------------------------------------------+
int CountTrades()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t!=0)
        {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
           {
            if(PositionGetInteger(POSITION_MAGIC)==20260915) c++;
           }
        }
     }
   return(c);
  }

//+------------------------------------------------------------------+
bool IsBuy()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t!=0)
        {
         if(PositionGetString(POSITION_SYMBOL)==_Symbol)
           {
            if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
               return(true);
            else
               return(false);
           }
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
double GetPts()
  {
   double tot=0;
   int cnt=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double o=PositionGetDouble(POSITION_PRICE_OPEN);
      double c=PositionGetDouble(POSITION_PRICE_CURRENT);
      long ty=PositionGetInteger(POSITION_TYPE);
      if(ty==POSITION_TYPE_BUY) tot+=(c-o)/_Point;
      else tot+=(o-c)/_Point;
      cnt++;
     }
   if(cnt>0) return(tot/cnt);
   return(0);
  }

//+------------------------------------------------------------------+
void CloseOne()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action=TRADE_ACTION_DEAL;
      req.symbol=_Symbol;
      req.volume=PositionGetDouble(POSITION_VOLUME);
      long tp=PositionGetInteger(POSITION_TYPE);
      if(tp==POSITION_TYPE_BUY) req.type=ORDER_TYPE_SELL;
      else req.type=ORDER_TYPE_BUY;
      if(req.type==ORDER_TYPE_BUY)
         req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      else
         req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      req.deviation=30;
      req.position=t;
      bool ok=OrderSend(req,res);
      if(ok) return;
     }
  }

//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      MqlTradeRequest req;
      MqlTradeResult res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action=TRADE_ACTION_DEAL;
      req.symbol=_Symbol;
      req.volume=PositionGetDouble(POSITION_VOLUME);
      long tp=PositionGetInteger(POSITION_TYPE);
      if(tp==POSITION_TYPE_BUY) req.type=ORDER_TYPE_SELL;
      else req.type=ORDER_TYPE_BUY;
      if(req.type==ORDER_TYPE_BUY)
         req.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      else
         req.price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      req.deviation=30;
      req.position=t;
      bool ok=OrderSend(req,res);
      if(!ok) Print("Close fail ",GetLastError());
     }
  }
//+------------------------------------------------------------------+
