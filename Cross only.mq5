//+------------------------------------------------------------------+
//| FINAL - GRAB 50% + RUNNER - CLOSE ONLY ON REVERSAL |
//+------------------------------------------------------------------+
#property strict
input double Lots = 0.01;
input int FastEMA = 5;
input int SlowEMA = 13;
input int ADX_Period = 14;
input int ADX_Threshold = 25;
input int FirstTarget = 80;
input int TrailDistance = 50;

int ema_fast, ema_slow, adx_handle, rsi_handle;
datetime lastCloseTime=0;
bool TradingEnabled=true;
bool halfClosed=false;

int OnInit()
  {
   ema_fast=iMA(_Symbol,PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   ema_slow=iMA(_Symbol,PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   adx_handle=iADX(_Symbol,PERIOD_M5,ADX_Period);
   rsi_handle=iRSI(_Symbol,PERIOD_M5,14,PRICE_CLOSE);
   ObjectCreate(0,"BTN_TRADE",OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XSIZE,130);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YSIZE,30);
   ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING");
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason){ IndicatorRelease(ema_fast); IndicatorRelease(ema_slow); IndicatorRelease(adx_handle); IndicatorRelease(rsi_handle); ObjectDelete(0,"BTN_TRADE"); Comment(""); }
void OnChartEvent(const int id,const long &l,const double &d,const string &s){ if(id==CHARTEVENT_OBJECT_CLICK && s=="BTN_TRADE"){ TradingEnabled=!TradingEnabled; if(TradingEnabled){ ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);} else{ ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"START TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrRed);} ChartRedraw(); } }

void OnTick()
  {
   double f[],s[],adx[],rsi[];
   if(CopyBuffer(ema_fast,0,0,3,f)!=3) return;
   if(CopyBuffer(ema_slow,0,0,3,s)!=3) return;
   if(CopyBuffer(adx_handle,0,0,3,adx)!=3) return;
   if(CopyBuffer(rsi_handle,0,0,3,rsi)!=3) return;
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(adx,true); ArraySetAsSeries(rsi,true);

   bool freshBuy = f[2]<=s[2] && f[1]>s[1];
   bool freshSell = f[2]>=s[2] && f[1]<s[1];
   bool oppositeBuy = f[2]>=s[2] && f[1]<s[1]; // reversal for buy position
   bool oppositeSell = f[2]<=s[2] && f[1]>s[1]; // reversal for sell position
   double dist=MathAbs(f[1]-s[1])/_Point;
   int cnt=CountTrades(); double pts=GetPts();

   bool strongTrend = adx[1] > ADX_Threshold && dist > 30;
   bool reversalDetected = adx[1]<20 || (cnt>0 && PositionIsBuy() && rsi[1]<52) || (cnt>0 &&!PositionIsBuy() && rsi[1]>48);

   Comment("=== FINAL GRAB+RUNNER ===\n","Trend:",(f[1]>s[1]?"BUY":"SELL")," ADX:",DoubleToString(adx[1],1)," Dist:",DoubleToString(dist,1),"\n",
           "Trades:",cnt,"/2 Profit:",DoubleToString(pts,1),"pts HalfClosed:",(halfClosed?"YES":"NO"),"\n",
           "Mode:",(cnt==0?"WAITING FOR CROSS":!halfClosed?"WAITING FOR 80pts TO GRAB":!reversalDetected?"RUNNER - LETTING IT RUN - NO REVERSAL":"REVERSAL DETECTED - WILL CLOSE"),"\n",
           "Rule: Close FULLY only on reversal");

   if(!TradingEnabled) return;
   if(cnt>=1)
     {
      // STEP 1: Grab half at 80pts
      if(!halfClosed && pts>=FirstTarget && cnt==2)
        {
         CloseOneTrade(); // Grab 1
         halfClosed=true;
         return;
        }
      // STEP 2: Keep runner until REVERSAL ONLY
      if(halfClosed)
        {
         if((PositionIsBuy() && oppositeBuy) || (!PositionIsBuy() && oppositeSell) || reversalDetected)
           { CloseAll(); halfClosed=false; lastCloseTime=TimeCurrent(); return; }
         return; // Don't close, let it run
        }
      return;
     }

   // No trades - wait for fresh cross
   if(TimeCurrent()-lastCloseTime < 60) return;
   if(!freshBuy &&!freshSell) return;
   if(!strongTrend) return;
   if(CountTrades()>=2) return;

   // Open 2 trades = 0.01+0.01
   halfClosed=false;
   if(freshBuy && rsi[1]<70 && rsi[1]>50){ OpenTwo(ORDER_TYPE_BUY); }
   else if(freshSell && rsi[1]>30 && rsi[1]<50){ OpenTwo(ORDER_TYPE_SELL); }
  }

void OpenTwo(ENUM_ORDER_TYPE type){ for(int i=0;i<2;i++){ if(CountTrades()>=2) return; MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); double price=(type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lots; req.type=type; req.price=price; req.deviation=30; req.magic=20260915; if(!OrderSend(req,res)) Print("Fail ",GetLastError()); Sleep(300);} }
int CountTrades(){ int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==20260915) c++; } return(c); }
bool PositionIsBuy(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) return(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY); } return(false); }
double GetPts(){ double tot=0; int cnt=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; double o=PositionGetDouble(POSITION_PRICE_OPEN); double cu=PositionGetDouble(POSITION_PRICE_CURRENT); long ty=PositionGetInteger(POSITION_TYPE); tot+= (ty==POSITION_TYPE_BUY)? (cu-o)/_Point : (o-cu)/_Point; cnt++; } return(cnt>0?tot/cnt:0); }
void CloseOneTrade(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=PositionGetDouble(POSITION_VOLUME); req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); req.price=(req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=30; req.position=t; if(OrderSend(req,res)){ Print("GRABBED 50% PROFIT - Runner kept"); return; } } }
void CloseAll(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=PositionGetDouble(POSITION_VOLUME); req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); req.price=(req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=30; req.position=t; OrderSend(req,res); } }
