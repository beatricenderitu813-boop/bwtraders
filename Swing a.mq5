#property strict
input double LotSize=0.01;
input int HoldMinutes=240;
input int EMA_Fast=9;
input int EMA_Slow=21;

int hF,hS;
datetime lastBar=0;
bool TradingON=false;

int OnInit(){
 hF=iMA(_Symbol,PERIOD_H1,EMA_Fast,0,MODE_EMA,PRICE_CLOSE);
 hS=iMA(_Symbol,PERIOD_H1,EMA_Slow,0,MODE_EMA,PRICE_CLOSE);
 CreateButtons();
 Print("SWING BUTTON EA READY - Press START");
 return(INIT_SUCCEEDED);
}
void OnDeinit(const int r){
 ObjectDelete(0,"BtnStart");
 ObjectDelete(0,"BtnStop");
 IndicatorRelease(hF); IndicatorRelease(hS);
}

void CreateButtons(){
 ObjectCreate(0,"BtnStart",OBJ_BUTTON,0,0,0);
 ObjectSetInteger(0,"BtnStart",OBJPROP_XDISTANCE,20);
 ObjectSetInteger(0,"BtnStart",OBJPROP_YDISTANCE,20);
 ObjectSetInteger(0,"BtnStart",OBJPROP_XSIZE,90);
 ObjectSetInteger(0,"BtnStart",OBJPROP_YSIZE,35);
 ObjectSetString(0,"BtnStart",OBJPROP_TEXT,"START");
 ObjectSetInteger(0,"BtnStart",OBJPROP_BGCOLOR,clrLimeGreen);
 ObjectSetInteger(0,"BtnStart",OBJPROP_COLOR,clrBlack);
 ObjectSetInteger(0,"BtnStart",OBJPROP_FONTSIZE,10);

 ObjectCreate(0,"BtnStop",OBJ_BUTTON,0,0,0);
 ObjectSetInteger(0,"BtnStop",OBJPROP_XDISTANCE,120);
 ObjectSetInteger(0,"BtnStop",OBJPROP_YDISTANCE,20);
 ObjectSetInteger(0,"BtnStop",OBJPROP_XSIZE,90);
 ObjectSetInteger(0,"BtnStop",OBJPROP_YSIZE,35);
 ObjectSetString(0,"BtnStop",OBJPROP_TEXT,"STOP & CLOSE");
 ObjectSetInteger(0,"BtnStop",OBJPROP_BGCOLOR,clrTomato);
 ObjectSetInteger(0,"BtnStop",OBJPROP_COLOR,clrWhite);
 ObjectSetInteger(0,"BtnStop",OBJPROP_FONTSIZE,10);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam){
 if(id==CHARTEVENT_OBJECT_CLICK){
  if(sparam=="BtnStart"){
   TradingON=true;
   Print("TRADING STARTED - Will hold up to ",HoldMinutes," mins, check at 4pm");
   ObjectSetInteger(0,"BtnStart",OBJPROP_STATE,false);
  }
  if(sparam=="BtnStop"){
   TradingON=false;
   Print("STOP PRESSED - Closing all");
   CloseAll();
   ObjectSetInteger(0,"BtnStop",OBJPROP_STATE,false);
  }
 }
}

bool CloseAll(){
 bool ok=true;
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong tk=PositionGetTicket(i); if(tk==0) continue;
  if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
  if(!PositionSelectByTicket(tk)) continue;
  MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
  rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=PositionGetDouble(POSITION_VOLUME);
  rq.position=tk; rq.type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
  rq.price=(rq.type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
  rq.deviation=100; rq.type_filling=ORDER_FILLING_IOC;
  if(!OrderSend(rq,rs)){
   rq.type_filling=ORDER_FILLING_FOK;
   OrderSend(rq,rs);
  }
 }
 return ok;
}

void OnTick(){
 // Auto close after 4 hours even if you forget
 datetime now=TimeCurrent();
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong tk=PositionGetTicket(i); if(tk==0) continue;
  if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
  if(!PositionSelectByTicket(tk)) continue;
  datetime ot=(datetime)PositionGetInteger(POSITION_TIME);
  int mins=(int)((now-ot)/60);
  if(mins>=HoldMinutes){
   MqlTradeRequest rq; MqlTradeResult rs; ZeroMemory(rq); ZeroMemory(rs);
   rq.action=TRADE_ACTION_DEAL; rq.symbol=_Symbol; rq.volume=PositionGetDouble(POSITION_VOLUME);
   rq.position=tk; rq.type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   rq.price=(rq.type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   rq.deviation=100; rq.type_filling=ORDER_FILLING_IOC;
   OrderSend(rq,rs);
   Print("AUTO-CLOSED after ",HoldMinutes," mins - check at 4pm");
  }
 }

 if(!TradingON) return;
 int cnt=0; for(int i=0;i<PositionsTotal();i++){ if(PositionGetTicket(i)!=0) if(PositionGetString(POSITION_SYMBOL)==_Symbol) cnt++; }
 if(cnt>=1) return;
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
