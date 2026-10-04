//+------------------------------------------------------------------+
//|                                      RsiSupportResistanceEA.mq5  |
//|                                              Copyright 2026      |
//|  RSI + Support/Resistance Expert Advisor for MetaTrader 5        |
//|  Works on any symbol and any timeframe.                          |
//+------------------------------------------------------------------+
#property copyright "Base44"
#property version   "1.00"
#property description "RSI + Support/Resistance EA. Works on any symbol and timeframe."

#include <Trade\Trade.mqh>

//--- RSI inputs
input group "=== RSI ==="
input int      InpRsiPeriod      = 14;        // RSI period
input double   InpRsiOversold    = 30.0;      // Oversold level (buy zone)
input double   InpRsiOverbought  = 70.0;      // Overbought level (sell zone)

//--- Support / Resistance inputs
input group "=== Support / Resistance ==="
input int      InpSrLookback     = 100;       // Bars to scan for S/R levels
input int      InpSrStrength     = 3;         // Pivot strength (bars each side)
input int      InpSrMaxLevels    = 4;         // Max levels kept per side
input double   InpSrProximityATR = 0.5;       // Proximity to level (x ATR)

//--- Risk / money management
input group "=== Risk / Money Management ==="
input double   InpRiskPercent    = 1.0;       // Risk per trade (% of balance)
input double   InpFixedLot       = 0.0;       // Fixed lot (0 = use risk %)
input double   InpStopLossATR    = 2.0;       // Stop loss (x ATR)
input double   InpTakeProfitATR  = 3.0;       // Take profit (x ATR)
input int      InpAtrPeriod      = 14;        // ATR period
input bool     InpUseBreakEven   = true;      // Move SL to break-even
input double   InpBreakEvenATR   = 1.0;       // Break-even trigger (x ATR)
input int      InpMaxPositions   = 1;         // Max simultaneous positions

//--- General
input group "=== General ==="
input long     InpMagic          = 20261004;  // Magic number
input int      InpSlippage       = 20;        // Slippage (points)
input bool     InpOnePerBar      = true;      // Only one entry per bar

//--- globals
CTrade   trade;
int      hRsi = INVALID_HANDLE;
int      hAtr = INVALID_HANDLE;
datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   hRsi = iRSI(_Symbol, PERIOD_CURRENT, InpRsiPeriod, PRICE_CLOSE);
   hAtr = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);

   if(hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hRsi != INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- break-even management runs on every tick
   if(InpUseBreakEven)
      ManageBreakEven();

   //--- one entry per bar (optional)
   bool newBar = IsNewBar();
   if(InpOnePerBar && !newBar)
      return;

   if(CountPositions() >= InpMaxPositions)
      return;

   double atr = GetIndicatorValue(hAtr, 1);
   double rsi = GetIndicatorValue(hRsi, 1);
   if(atr <= 0.0)
      return;

   double supports[], resistances[];
   FindLevels(supports, false);
   FindLevels(resistances, true);

   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double close     = iClose(_Symbol, PERIOD_CURRENT, 1);
   double tolerance = InpSrProximityATR * atr;

   //--- BUY: oversold RSI near support
   if(rsi < InpRsiOversold && IsNearLevel(close, supports, tolerance))
   {
      double sl      = NormalizeDouble(close - InpStopLossATR * atr, _Digits);
      double tp      = NormalizeDouble(close + InpTakeProfitATR * atr, _Digits);
      double lot     = CalcLot(ask - sl);
      if(lot > 0.0 && sl < ask && tp > ask)
         trade.Buy(lot, _Symbol, ask, sl, tp, "RSI+SR Buy");
   }
   //--- SELL: overbought RSI near resistance
   else if(rsi > InpRsiOverbought && IsNearLevel(close, resistances, tolerance))
   {
      double sl      = NormalizeDouble(close + InpStopLossATR * atr, _Digits);
      double tp      = NormalizeDouble(close - InpTakeProfitATR * atr, _Digits);
      double lot     = CalcLot(sl - bid);
      if(lot > 0.0 && sl > bid && tp < bid)
         trade.Sell(lot, _Symbol, bid, sl, tp, "RSI+SR Sell");
   }
}

//+------------------------------------------------------------------+
//| Read a value from an indicator buffer at a given shift           |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int shift)
{
   double buf[];
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
      return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Detect a new bar on the current chart                            |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == lastBarTime)
      return false;
   lastBarTime = t;
   return true;
}

//+------------------------------------------------------------------+
//| Count open positions belonging to this EA on this symbol         |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Collect recent support or resistance levels (pivot based)        |
//+------------------------------------------------------------------+
void FindLevels(double &levels[], bool findResistance)
{
   ArrayResize(levels, 0);
   int total = Bars(_Symbol, PERIOD_CURRENT);
   int bars  = MathMin(InpSrLookback, total - InpSrStrength - 1);
   int count = 0;

   for(int i = InpSrStrength + 1; i <= bars; i++)
   {
      double price = findResistance
                     ? iHigh(_Symbol, PERIOD_CURRENT, i)
                     : iLow(_Symbol, PERIOD_CURRENT, i);

      bool isPivot = findResistance
                     ? IsPivotHigh(i, InpSrStrength)
                     : IsPivotLow(i, InpSrStrength);

      if(!isPivot)
         continue;

      if(LevelExists(levels, price, _Point * 10))
         continue;

      ArrayResize(levels, count + 1);
      levels[count] = price;
      count++;

      if(count >= InpSrMaxLevels)
         break;
   }
}

//+------------------------------------------------------------------+
//| Pivot helpers                                                    |
//+------------------------------------------------------------------+
bool IsPivotHigh(int index, int strength)
{
   double h = iHigh(_Symbol, PERIOD_CURRENT, index);
   for(int i = 1; i <= strength; i++)
   {
      if(iHigh(_Symbol, PERIOD_CURRENT, index + i) >= h) return false;
      if(iHigh(_Symbol, PERIOD_CURRENT, index - i) >= h) return false;
   }
   return true;
}

bool IsPivotLow(int index, int strength)
{
   double l = iLow(_Symbol, PERIOD_CURRENT, index);
   for(int i = 1; i <= strength; i++)
   {
      if(iLow(_Symbol, PERIOD_CURRENT, index + i) <= l) return false;
      if(iLow(_Symbol, PERIOD_CURRENT, index - i) <= l) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check whether a price is already stored in the level list        |
//+------------------------------------------------------------------+
bool LevelExists(double &levels[], double price, double tolerance)
{
   for(int i = 0; i < ArraySize(levels); i++)
      if(MathAbs(levels[i] - price) <= tolerance)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Check whether a price is close to any level in the list          |
//+------------------------------------------------------------------+
bool IsNearLevel(double price, double &levels[], double tolerance)
{
   for(int i = 0; i < ArraySize(levels); i++)
      if(MathAbs(price - levels[i]) <= tolerance)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Risk-based position sizing                                       |
//+------------------------------------------------------------------+
double CalcLot(double stopDistance)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(InpFixedLot > 0.0)
      return NormalizeLot(InpFixedLot);

   if(stopDistance <= 0.0)
      return NormalizeLot(minLot);

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return NormalizeLot(minLot);

   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return NormalizeLot(minLot);

   return NormalizeLot(riskAmount / lossPerLot);
}

//+------------------------------------------------------------------+
//| Clamp a lot size to the symbol's allowed range and step          |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      step = 0.01;

   lot = MathFloor(lot / step) * step;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;

   int lotDigits = (int)MathMax(0, MathCeil(-MathLog10(step)));
   return NormalizeDouble(lot, lotDigits);
}

//+------------------------------------------------------------------+
//| Move stop loss to break-even once a position is in profit        |
//+------------------------------------------------------------------+
void ManageBreakEven()
{
   double atr = GetIndicatorValue(hAtr, 1);
   if(atr <= 0.0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid - open >= InpBreakEvenATR * atr && (sl < open || sl == 0.0))
            trade.PositionModify(ticket, NormalizeDouble(open, _Digits), tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(open - ask >= InpBreakEvenATR * atr && (sl > open || sl == 0.0))
            trade.PositionModify(ticket, NormalizeDouble(open, _Digits), tp);
      }
   }
}
//+------------------------------------------------------------------+
