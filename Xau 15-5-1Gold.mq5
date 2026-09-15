input bool UseNYFilter=false; // OFF for testing
input double PullbackMaxDist=3.0; // Looser

string Get5MPullback(string t) {
  double ema[]; ArraySetAsSeries(ema,true);
  CopyBuffer(iMA(_Symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE),0,0,2,ema);
  double c=iClose(_Symbol,PERIOD_M5,1);
  double dist = MathAbs(c - ema[0]);
  if(dist <= PullbackMaxDist) return "PULLBACK OK";
  return "WAITING PULLBACK";
}
