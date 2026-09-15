//+------------------------------------------------------------------+
//|  HIGH PROBABILITY GRAB + TRAIL - 1 Trade, Confidence Filter      |
//+------------------------------------------------------------------+
#property strict
input double Lots = 0.01;
input int FastEMA = 5;
input int SlowEMA = 13; // 5 & 13 is more stable than 5 & 8
input int ADX_Period = 14;
input int ADX_Threshold = 25; // Only trade strong trend
input int TargetPoints = 80;  // First target
input int TrailStart = 80;    // Start trailing after 80pts
input int TrailDistance = 40; // Trail by 40pts
input double MaxDailyLoss = 3.0; // Stop if -$3 today

int ema_fast, ema_slow, adx_handle, rsi_handle;
datetime lastCloseTime=0;
bool TradingEnabled=true;
bool isTrailing=false;
double dailyLoss=0;
datetime lastDay=0;

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
void OnChartEvent(const int id,const long &l,const double &d,const string &s){ if(id==CHARTEVENT_OBJECT_CLICK && s=="BTN_TRADE"){ TradingEnabled=!TradingEnabled; if(TradingEnabled){ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);} else{ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"START TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrRed);} ChartRedraw(); } }

void OnTick()
  {
   // Reset daily loss at new day
   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   datetime today=StructToTime(tm); today=today-tm.hour*3600-tm.min*60-tm.sec;
   if(lastDay!=today){ dailyLoss=0; lastDay=today; }

   double f[],s[],adx[],rsi[]; 
   if(CopyBuffer(ema_fast,0,0,3,f)!=3) return;
   if(CopyBuffer(ema_slow,0,0,3,s)!=3) return;
   if(CopyBuffer(adx_handle,0,0,3,adx)!=3) return;
   if(CopyBuffer(rsi_handle,0,0,3,rsi)!=3) return;
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(adx,true); ArraySetAsSeries(rsi,true);

   bool freshBuy = f[2]<=s[2] && f[1]>s[1];
   bool freshSell = f[2]>=s[2] && f[1]<s[1];
   double dist=MathAbs(f[1]-s[1])/_Point;
   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point/_Point;

   int cnt=CountTrades(); double pts=GetPts(); double money=GetMoney();
   bool strongTrend = adx[1] > ADX_Threshold && dist > 30;
   bool rsiOK_Buy = rsi[1] < 70 && rsi[1] > 50;
   bool rsiOK_Sell = rsi[1] > 30 && rsi[1] < 50;

   Comment("=== HIGH CONFIDENCE BOT ===\n","Trend:",(f[1]>s[1]?"BUY":"SELL")," Dist:",DoubleToString(dist,1)," ADX:",DoubleToString(adx[1],1),"\n",
           "Strong:",(strongTrend?"YES 80%":"NO - SKIP")," RSI:",DoubleToString(rsi[1],1),"\n",
           "Trades:",cnt,"/1 Profit:",DoubleToString(pts,1),"pts $",DoubleToString(money,2),"\n",
           "Daily Loss $",DoubleToString(dailyLoss,2),"/",DoubleToString(MaxDailyLoss,2),"\n",
           "Mode:",(isTrailing?"TRAILING - letting it run":"WAITING FOR 80pts"));

   // Risk Management
   if(dailyLoss >= MaxDailyLoss){ Comment("DAILY LOSS LIMIT REACHED - STOPPED FOR TODAY"); return; }
   if(spread > 400){ Comment("SPREAD TOO HIGH - SKIP"); return; } // Gold spread filter
   if(!TradingEnabled) return;
   if(cnt>=1)
     {
      // SMART CLOSE LOGIC: Don't close if strong trend continues
      if(pts >= TrailStart && strongTrend)
        {
         isTrailing=true; // Keep running, trail later
         // Close only if momentum weakens: RSI reverses or ADX drops
         if((f[1]>s[1] && rsi[1]<55) || (f[1]<s[1] && rsi[1]>45) || adx[1]<20)
           { CloseAll(); isTrailing=false; lastCloseTime=TimeCurrent(); }
         return;
        }
      if(pts >= TargetPoints && !isTrailing)
        { CloseAll(); isTrailing=false; lastCloseTime=TimeCurrent(); return; }
      return;
     }

   isTrailing=false;
   if(TimeCurrent()-lastCloseTime < 60) return; // 1 min cooldown
   if(!freshBuy && !freshSell) return;
   if(!strongTrend) return; // 80% filter - skip weak trends

   if(freshBuy && rsiOK_Buy){ OpenOne(ORDER_TYPE_BUY); }
   else if(freshSell && rsiOK_Sell){ OpenOne(ORDER_TYPE_SELL); }
  }

void OpenOne(ENUM_ORDER_TYPE type)
  {
   if(CountTrades()>=1) return; // CRITICAL FIX: Never open 6 at once
   MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
   double price=(type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lots; req.type=type; req.price=price; req.deviation=30; req.magic=20260915;
   if(!OrderSend(req,res)) Print("Order failed ",GetLastError());
  }
int CountTrades(){ int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==20260915) c++; } return(c); }
double GetPts(){ double tot=0; int cnt=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; double o=PositionGetDouble(POSITION_PRICE_OPEN); double cu=PositionGetDouble(POSITION_PRICE_CURRENT); long ty=PositionGetInteger(POSITION_TYPE); tot+= (ty==POSITION_TYPE_BUY)? (cu-o)/_Point : (o-cu)/_Point; cnt++; } return(cnt>0?tot/cnt:0); }
double GetMoney(){ double p=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) p+=PositionGetDouble(POSITION_PROFIT); } return(p); }
void CloseAll()
  { 
   double profitBefore=GetMoney();
   for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=PositionGetDouble(POSITION_VOLUME); req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); req.price=(req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=30; req.position=t; if(!OrderSend(req,res)) Print("Close fail ",GetLastError()); else { if(profitBefore<0) dailyLoss+=MathAbs(profitBefore); } } 
  }
