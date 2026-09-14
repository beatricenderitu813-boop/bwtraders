#property strict
input double LotSize=0.01;
input double ProfitUSD=2.00;
input double LossUSD=2.00;
input int HoldMinutes=240;
input int MaxTrades=1;
input int EMA_Fast=9;
input int EMA_Slow=21;
int hF,hS;
datetime lastBar=0;

int OnInit(){hF=iMA(_Symbol,PERIOD_H1,EMA_Fast,0,MODE_EMA,PRICE_CLOSE); hS=iMA(_Symbol,PERIOD_H1,EMA_Slow,0,MODE_EMA,PRICE_CLOSE); return(INIT_SUCCEEDED);}

bool ClosePos(ulong ticket){
 if(!PositionSelectByTicket(ticket)) return false;
 string sym=PositionGetString(POSITION_SYMBOL);
 double vol=PositionGetDouble(POSITION_VOLUME);
 long type=PositionGetInteger(POSITION_TYPE);
 MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
 rq.action=TRADE_ACTION_DEAL; rq.symbol=sym; rq.volume=vol; rq.position=ticket;
 rq.type=(type==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
 rq.price=(rq.type==ORDER_TYPE_BUY)?SymbolInfoDouble(sym,SYMBOL_ASK):SymbolInfoDouble(sym,SYMBOL_BID);
 rq.deviation=100;
 rq.type_filling=ORDER_FILLING_IOC;
 // Try IOC then FOK if fail
 if(!OrderSend(rq,rs)){
  rq.type_filling=ORDER_FILLING_FOK;
  if(!OrderSend(rq,rs)){
   Print("Close fail ticket=",ticket," err=",GetLastError()," retcode=",rs.retcode);
   return false;
  }
 }
 Print("CLOSED ticket=",ticket," profit=",PositionGetDouble(POSITION_PROFIT));
 return true;
}

void OnTick(){
 datetime now=TimeCurrent();
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong tk=PositionGetTicket(i); if(tk==0) continue;
  if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
  if(!PositionSelectByTicket(tk)) continue;
  double pf=PositionGetDouble(POSITION_PROFIT);
  datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
  int mins=(int)((now-ot)/60);
  if(pf>=ProfitUSD || pf<=-LossUSD || mins>=HoldMinutes){
   ClosePos(tk);
  }
 }
 int cnt=0; for(int i=0;i<PositionsTotal();i++){ ulong t=PositionGetTicket(i); if(t==0) continue; if(PositionGetString(POSITION_SYMBOL)==_Symbol) cnt++; }
 if(cnt>=MaxTrades) return;
 datetime curBar=iTime(_Symbol,PERIOD_H1,0); if(curBar==lastBar) return; lastBar=curBar;
 double f[]; double s[]; ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);
 if(CopyBuffer(hF,0,0,2,f)<2) return;
 if(CopyBuffer(hS,0,0,2,s)<2) return;
 double b=SymbolInfoDouble(_Symbol,SYMBOL_BID);
 double o=iOpen(_Symbol,PERIOD_H1,0);
 if(f[0]>s[0] && b>o){
  MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
  rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=LotSize; rq.type=ORDER_TYPE_BUY;
  rq.price=SymbolInfoDouble(_Symbol,SYMBOL_ASK); rq.deviation=100; rq.type_filling=ORDER_FILLING_IOC;
  OrderSend(rq,rs);
 }
 if(f[0]<s[0] && b<o){
  MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
  rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=LotSize; rq.type=ORDER_TYPE_SELL;
  rq.price=SymbolInfoDouble(_Symbol,SYMBOL_BID); rq.deviation=100; rq.type_filling=ORDER_FILLING_IOC;
  OrderSend(rq,rs);
 }
}
