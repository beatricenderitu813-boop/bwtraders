//+------------------------------------------------------------------+
//| ULTRA FAST - 5 & 8 EMA - Re-enter every 5 sec - 80 pts target |
//+------------------------------------------------------------------+
#property strict
input double Lots = 0.01;
input int FastEMA = 5;   // FASTER - was 10
input int SlowEMA = 8;   // FASTER - was 20
input int TargetPoints = 80; // ~$1.60 with 2 trades
input int ReEnterDelaySeconds = 5; // Re-enter after 5 sec

int ema_fast, ema_slow;
datetime lastCloseTime=0;

int OnInit()
  {
   ema_fast = iMA(_Symbol, PERIOD_M5, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   ema_slow = iMA(_Symbol, PERIOD_M5, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
  }
void OnDeinit(const int reason){ IndicatorRelease(ema_fast); IndicatorRelease(ema_slow); Comment(""); }

void OnTick()
  {
   ShowInfo();
   if(CountTrades()>=1 && GetPts()>=TargetPoints){ CloseAll(); lastCloseTime=TimeCurrent(); return; }
   if(CountTrades()>=2) return;
   if(TimeCurrent()-lastCloseTime < ReEnterDelaySeconds) return;

   double f[],s[]; CopyBuffer(ema_fast,0,0,3,f); ArraySetAsSeries(f,true); CopyBuffer(ema_slow,0,0,3,s); ArraySetAsSeries(s,true);

   if(f[1]>s[1]) OpenTwo(ORDER_TYPE_BUY);
   else if(f[1]<s[1]) OpenTwo(ORDER_TYPE_SELL);
  }

void ShowInfo()
  {
   double f[],s[]; CopyBuffer(ema_fast,0,0,3,f); ArraySetAsSeries(f,true); CopyBuffer(ema_slow,0,0,3,s); ArraySetAsSeries(s,true);
   double dist = MathAbs(f[1]-s[1])/_Point;
   string trend = f[1]>s[1] ? "UP -> BUYING" : "DOWN -> SELLING";
   string next = (TimeCurrent()-lastCloseTime >= ReEnterDelaySeconds) ? "READY!" : IntegerToString(ReEnterDelaySeconds-(TimeCurrent()-lastCloseTime))+"s";

   Comment("=== ULTRA FAST SCALPER ===\n"
           + "EMA 5 & 8 - M5 GOLD\n"
           + "Trend: "+trend+"\n"
           + "Distance: "+DoubleToString(dist,1)+" pts (Cross when ~0)\n"
           + "Trades: "+IntegerToString(CountTrades())+"/2\n"
           + "Profit: "+DoubleToString(GetPts(),1)+" pts / $"+DoubleToString(GetMoney(),2)+"\n"
           + "Target: 80 pts (~$1.60)\n"
           + "Next Entry: "+next+"\n"
           + "Cross Speed: Every 5-15 mins");
  }

void OpenTwo(ENUM_ORDER_TYPE type){ for(int i=0;i<2;i++){ MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); double price=(type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=Lots; req.type=type; req.price=price; req.deviation=30; req.magic=1111; OrderSend(req,res); Sleep(150); } }
int CountTrades(){ int c=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) c++; } return(c); }
double GetPts(){ double tot=0; int cnt=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; double o=PositionGetDouble(POSITION_PRICE_OPEN); double cu=PositionGetDouble(POSITION_PRICE_CURRENT); long ty=PositionGetInteger(POSITION_TYPE); tot+= (ty==POSITION_TYPE_BUY)? (cu-o)/_Point : (o-cu)/_Point; cnt++; } return(cnt>0?tot/cnt:0); }
double GetMoney(){ double p=0; for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol) p+=PositionGetDouble(POSITION_PROFIT); } return(p); }
void CloseAll(){ for(int i=PositionsTotal()-1;i>=0;i--){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue; MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req); req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.volume=PositionGetDouble(POSITION_VOLUME); req.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); req.price=(req.type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID); req.deviation=30; req.position=t; OrderSend(req,res); } Print("80 PTS DONE - Re-entering in 5s"); }
