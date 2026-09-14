#property strict
input double LotSize=0.01;
input double ProfitUSD=0.40;
input double LossUSD=1.00;
input int HoldMinutes=240;
input int MaxTrades=1;
input int EMA_Fast=9;
input int EMA_Slow=21;
int hF,hS;
int OnInit(){hF=iMA(_Symbol,PERIOD_H1,EMA_Fast,0,MODE_EMA,PRICE_CLOSE); hS=iMA(_Symbol,PERIOD_H1,EMA_Slow,0,MODE_EMA,PRICE_CLOSE); Print("4H HOLD EA STARTED Hold=",HoldMinutes,"min"); return(INIT_SUCCEEDED);}
void OnDeinit(const int r){IndicatorRelease(hF); IndicatorRelease(hS);}
void OnTick(){
 datetime now=TimeCurrent();
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong tk=PositionGetTicket(i); if(tk==0) continue;
  if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
  double pf=PositionGetDouble(POSITION_PROFIT);
  datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
  int mins=(int)((now-ot)/60);
  if(pf>=ProfitUSD || pf<=-LossUSD || mins>=HoldMinutes){
   MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
   rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=PositionGetDouble(POSITION_VOLUME);
   rq.type=(ENUM_ORDER_TYPE)(1-PositionGetInteger(POSITION_TYPE)); rq.position=tk;
   rq.price=(rq.type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   rq.deviation=100;
   bool ok=OrderSend(rq,rs);
   if(ok) Print("CLOSED pf=",pf," mins=",mins);
   else Print("Close fail ",GetLastError());
  }
 }
 int cnt=0; for(int i=0;i<PositionsTotal();i++){ if(PositionGetTicket(i)!=0) if(PositionGetString(POSITION_SYMBOL)==_Symbol) cnt++; }
 if(cnt>=MaxTrades) return;
 double f[]; double s[]; ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);
 if(CopyBuffer(hF,0,0,2,f)<2) return;
 if(CopyBuffer(hS,0,0,2,s)<2) return;
 double o=iOpen(_Symbol,PERIOD_H1,0); double b=SymbolInfoDouble(_Symbol,SYMBOL_BID); if(o==0) return;
 if(f[0]>s[0] && b>o){
  MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
  rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=LotSize; rq.type=ORDER_TYPE_BUY;
  rq.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK); rq.deviation=100;
  bool ok=OrderSend(rq,rs); if(ok) Print("BUY opened, check at 4pm");
 }
 if(f[0]<s[0] && b<o){
  MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
  rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=LotSize; rq.type=ORDER_TYPE_SELL;
  rq.price=SymbolInfoDouble(_Symbol,SYMBOL_BID); rq.deviation=100;
  bool ok=OrderSend(rq,rs); if(ok) Print("SELL opened, check at 4pm");
 }
}
