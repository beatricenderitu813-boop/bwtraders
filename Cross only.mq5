//+------------------------------------------------------------------+
//| CROSS ONLY - Trade only on FRESH CROSS - No re-entry |
//+------------------------------------------------------------------+
#property strict
input double Lots = 0.01;
input int FastEMA = 5;
input int SlowEMA = 8;
input int TargetPoints = 80;
input int CooldownSeconds = 60; // Wait 1 min after close

int ema_fast, ema_slow;
datetime lastCloseTime=0;
bool TradingEnabled=true;
bool hasOpenTrade=false; // Lock after opening until new cross
int lastCrossDir=0; // 1=buy cross, -1=sell cross, 0=none

int OnInit()
  {
   ema_fast=iMA(_Symbol,PERIOD_M5,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   ema_slow=iMA(_Symbol,PERIOD_M5,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   ObjectCreate(0,"BTN_TRADE",OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_XSIZE,130);
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_YSIZE,30);
   ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING");
   ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason){ IndicatorRelease(ema_fast); IndicatorRelease(ema_slow); ObjectDelete(0,"BTN_TRADE"); Comment(""); }
void OnChartEvent(const int id,const long &l,const double &d,const string &s){ if(id==CHARTEVENT_OBJECT_CLICK && s=="BTN_TRADE"){ TradingEnabled=!TradingEnabled; if(TradingEnabled){ ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime);} else{ ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"START TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrRed);} ChartRedraw(); } }

void OnTick()
  {
   double f[],s[]; if(CopyBuffer(ema_fast,0,0,3,f)!=3) return; if(CopyBuffer(ema_slow,0,0,3,s)!=3) return;
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);

   bool freshBuyCross = f[2]<=s[2] && f[1]>s[1];
   bool freshSellCross = f[2]>=s[2] && f[1]<s[1];

   // If we got a fresh cross, unlock trading
   if(freshBuyCross){ lastCrossDir=1; hasOpenTrade=false; Print("FRESH BUY CROSS"); }
   if(freshSellCross){ lastCrossDir=-1; hasOpenTrade=false; Print("FRESH SELL CROSS"); }

   double pts=GetPts(); int cnt=CountTrades();
   Comment("=== CROSS ONLY FIXED ===\n","Fresh Buy:",freshBuyCross," Sell:",freshSellCross,"\n",
           "Last Cross:",(lastCrossDir==1?"BUY":lastCrossDir==-1?"SELL":"NONE")," | Locked:",hasOpenTrade,"\n",
           "Trades:",cnt,"/2 Profit:",DoubleToString(pts,1),"pts $",DoubleToString(GetMoney(),2),"\n",
           "Rule: ONLY trades on NEW CROSS");

   if(cnt>=1 && pts>=TargetPoints){ CloseAll(); lastCloseTime=TimeCurrent(); hasOpenTrade=true; return; } // Lock after close
   if(!TradingEnabled) return;
   if(cnt>=2) return;
   if(TimeCurrent()-lastCloseTime < CooldownSeconds) return;
   if(hasOpenTrade) return; // CRITICAL: Don't re-enter until new cross
   if(cnt>=1) return; // Already in trade, don't add more

   if(freshBuyCross){ OpenTwo(ORDER_TYPE_BUY); hasOpenTrade=true; }
   else if(freshSellCross){ OpenTwo(ORDER_TYPE_SELL); hasOpenTrade=true; }
  }

void OpenTwo(ENUM_ORDER_TYPE type){ for(int i=0;i<2;i++){ MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); double price=(type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lots; req.type=type; req.price=price; req.deviation=30; req.magic=1111; if(!OrderSend(req,res)) Print("Fail ",GetLastError()); Sleep(200);} }
int CountTrades(){ int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) c++; } return(c); }
double GetPts(){ double tot=0; int cnt=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; double o=PositionGetDouble(POSITION_PRICE_OPEN); double cu=PositionGetDouble(POSITION_PRICE_CURRENT); long ty=PositionGetInteger(POSITION_TYPE); tot+= (ty==POSITION_TYPE_BUY)? (cu-o)/_Point : (o-cu)/_Point; cnt++; } return(cnt>0?tot/cnt:0); }
double GetMoney(){ double p=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) p+=PositionGetDouble(POSITION_PROFIT); } return(p); }
void CloseAll(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=PositionGetDouble(POSITION_VOLUME); req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); req.price=(req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=30; req.position=t; if(!OrderSend(req,res)) Print("Close fail ",GetLastError()); } }
