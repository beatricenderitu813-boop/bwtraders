//+------------------------------------------------------------------+
//| SMART FAST - Only re-enter after PROFIT, not after LOSS |
//+------------------------------------------------------------------+
#property strict
input double Lots = 0.01;
input int FastEMA = 5;
input int SlowEMA = 8;
input int TargetPoints = 80;
input int ReEnterDelaySeconds = 5;
input int LossCooldownSeconds = 300; // Wait 5 min after loss

int ema_fast, ema_slow;
datetime lastCloseTime=0;
bool TradingEnabled=true;
bool LastTradeWasProfit=true; // Start assuming profit
double lastProfitDollars=0;

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
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason){ IndicatorRelease(ema_fast); IndicatorRelease(ema_slow); ObjectDelete(0,"BTN_TRADE"); Comment(""); }
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_CLICK && sparam=="BTN_TRADE")
     { TradingEnabled=!TradingEnabled;
       if(TradingEnabled){ ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"STOP TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrLime); }
       else{ ObjectSetString(0,"BTN_TRADE",OBJPROP_TEXT,"START TRADING"); ObjectSetInteger(0,"BTN_TRADE",OBJPROP_BGCOLOR,clrRed); }
       ChartRedraw(); }
  }

void OnTick()
  {
   double f[],s[]; if(CopyBuffer(ema_fast,0,0,3,f)!=3) return; if(CopyBuffer(ema_slow,0,0,3,s)!=3) return;
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);
   double dist=MathAbs(f[1]-s[1])/_Point; double pts=GetPts(); double money=GetMoney(); int cnt=CountTrades();
   string lastResult = LastTradeWasProfit? "Last: PROFIT" : "Last: LOSS - cooling";
   string next;
   if(!LastTradeWasProfit) next = IntegerToString(LossCooldownSeconds-(int)(TimeCurrent()-lastCloseTime))+"s cooldown";
   else next = (TimeCurrent()-lastCloseTime >= ReEnterDelaySeconds)? "READY" : IntegerToString(ReEnterDelaySeconds-(int)(TimeCurrent()-lastCloseTime))+"s";

   Comment("=== SMART FAST 5&8 ===\n","Trend: ",(f[1]>s[1]?"UP BUY":"DOWN SELL")," | Dist: ",DoubleToString(dist,1),"\n",
           "Trades: ",cnt,"/2 | Profit: ",DoubleToString(pts,1),"pts $",DoubleToString(money,2),"\n",lastResult,"\n","Next: ",next);

   if(cnt>=1 && pts>=TargetPoints)
     {
      double profitBefore = GetMoney();
      CloseAll();
      lastCloseTime=TimeCurrent();
      // Check if that close was profit
      // We approximate: if pts >= Target, it was profit
      LastTradeWasProfit = true;
      lastProfitDollars = profitBefore;
      return;
     }

   // If we have loss and closed manually or SL, detect it
   // This part: if no trades and time passed, we can check last history? Simplified:
   if(cnt==0 && GetMoney()==0 && TimeCurrent()-lastCloseTime < 2)
     {
      // This was a just-closed position, we already set LastTradeWasProfit above for target hits
      // For manual closes that were loss, you would need history check - we keep it simple
     }

   if(!TradingEnabled) return;
   if(cnt>=2) return;

   // SMART LOGIC:
   if(!LastTradeWasProfit) // Last was LOSS
     {
      if(TimeCurrent()-lastCloseTime < LossCooldownSeconds) return; // Wait 5 minutes
      // After cooldown, only allow if NEW CROSS happened
      bool freshCrossBuy = f[2]<s[2] && f[1]>s[1];
      bool freshCrossSell = f[2]>s[2] && f[1]<s[1];
      if(!freshCrossBuy &&!freshCrossSell) return; // No fresh cross = don't enter
      // Reset after waiting
      LastTradeWasProfit=true;
     }
   else // Last was PROFIT - allow fast re-entry
     {
      if(TimeCurrent()-lastCloseTime < ReEnterDelaySeconds) return;
     }

   // Also detect loss from history - if last deals were negative, set flag
   if(cnt==0 && HistoryJustHadLoss()) { LastTradeWasProfit=false; lastCloseTime=TimeCurrent(); return; }

   if(f[1]>s[1]) OpenTwo(ORDER_TYPE_BUY);
   else if(f[1]<s[1]) OpenTwo(ORDER_TYPE_SELL);
  }

bool HistoryJustHadLoss()
  {
   // Check last 2 deals in history - if negative, it's a loss
   HistorySelect(TimeCurrent()-3600, TimeCurrent());
   int total=HistoryDealsTotal();
   if(total<2) return(false);
   double lastProfit=0;
   for(int i=total-1; i>=MathMax(0,total-2); i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      lastProfit+=HistoryDealGetDouble(ticket,DEAL_PROFIT);
     }
   if(lastProfit < 0) { Print("Last close was LOSS $",lastProfit," - cooling 5 min"); return(true); }
   return(false);
  }

void OpenTwo(ENUM_ORDER_TYPE type){ for(int i=0;i<2;i++){ MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); double price=(type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lots; req.type=type; req.price=price; req.deviation=30; req.magic=1111; if(!OrderSend(req,res)) Print("Order failed ",GetLastError()); Sleep(150);} }
int CountTrades(){ int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) c++; } return(c); }
double GetPts(){ double tot=0; int cnt=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; double o=PositionGetDouble(POSITION_PRICE_OPEN); double cu=PositionGetDouble(POSITION_PRICE_CURRENT); long ty=PositionGetInteger(POSITION_TYPE); tot+= (ty==POSITION_TYPE_BUY)? (cu-o)/_Point : (o-cu)/_Point; cnt++; } return(cnt>0?tot/cnt:0); }
double GetMoney(){ double p=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) p+=PositionGetDouble(POSITION_PROFIT); } return(p); }
void CloseAll(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=PositionGetDouble(POSITION_VOLUME); req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); req.price=(req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=30; req.position=t; if(!OrderSend(req,res)) Print("Close failed ",GetLastError()); } }
