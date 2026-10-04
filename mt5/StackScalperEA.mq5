//+------------------------------------------------------------------+
//|                                               StackScalperEA.mq5 |
//|                                              Copyright 2026      |
//|  Multi-order stacking scalper for MetaTrader 5.                  |
//|  Opens several identical positions per entry (like the reference  |
//|  XAUUSD clip), optional grid stacking, per-order TP/SL/trailing.  |
//|                                                                  |
//|  WARNING: stacking + grid multiplies risk. Test on demo first.    |
//+------------------------------------------------------------------+
#property copyright "Base44"
#property version   "1.00"
#property description "Multi-order stacking scalper. Opens N identical positions per entry, optional grid."

#include <Trade\Trade.mqh>

enum ENUM_ORDER_BIAS
{
   BIAS_BUY  = 0,  // Buy
   BIAS_SELL = 1   // Sell
};

//--- entry inputs
input group "=== Entries ==="
input int             InpOrdersPerBatch = 6;          // Orders opened per entry
input double          InpLotSize        = 0.17;       // Lot size per order
input ENUM_ORDER_BIAS InpBias           = BIAS_BUY;   // Direction

//--- grid inputs
input group "=== Grid stacking ==="
input bool  InpUseGrid        = true;                 // Add a batch as price moves against
input int   InpGridStepPoints = 2000;                 // Grid step (points)
input int   InpMaxBatches     = 5;                    // Max batches (safety cap)

//--- exit inputs
input group "=== Exits ==="
input int   InpTakeProfitPoints = 300;                // Take profit per order (points, 0 = off)
input int   InpStopLossPoints   = 0;                  // Stop loss per order (points, 0 = off)
input bool  InpUseTrailing      = false;              // Trailing stop
input int   InpTrailStartPoints = 400;                // Trailing start (points)
input int   InpTrailStepPoints  = 100;                // Trailing distance (points)

//--- general inputs
input group "=== General ==="
input long  InpMagic    = 20261005;                   // Magic number
input int   InpSlippage = 20;                         // Slippage (points)

//--- globals
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpOrdersPerBatch < 1)
   {
      Print("InpOrdersPerBatch must be at least 1");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(InpUseTrailing)
      ManageTrailing();

   int total   = CountPositions();
   int batches = total / InpOrdersPerBatch;
   bool isBuy  = (InpBias == BIAS_BUY);

   //--- first entry: open a full batch
   if(total == 0)
   {
      OpenBatch(isBuy);
      return;
   }

   //--- grid stacking
   if(!InpUseGrid || batches >= InpMaxBatches)
      return;

   double step = InpGridStepPoints * _Point;

   if(isBuy)
   {
      double lowest = LowestOpenPrice();
      double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(lowest > 0.0 && bid <= lowest - step)
         OpenBatch(true);
   }
   else
   {
      double highest = HighestOpenPrice();
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(highest > 0.0 && ask >= highest + step)
         OpenBatch(false);
   }
}

//+------------------------------------------------------------------+
//| Open one batch of identical positions                            |
//+------------------------------------------------------------------+
void OpenBatch(bool isBuy)
{
   double price = isBuy
                  ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double tp = 0.0;
   double sl = 0.0;

   if(InpTakeProfitPoints > 0)
      tp = NormalizeDouble(isBuy ? price + InpTakeProfitPoints * _Point
                                 : price - InpTakeProfitPoints * _Point, _Digits);
   if(InpStopLossPoints > 0)
      sl = NormalizeDouble(isBuy ? price - InpStopLossPoints * _Point
                                 : price + InpStopLossPoints * _Point, _Digits);

   for(int i = 0; i < InpOrdersPerBatch; i++)
   {
      if(isBuy)
         trade.Buy(InpLotSize, _Symbol, 0.0, sl, tp, "Stack");
      else
         trade.Sell(InpLotSize, _Symbol, 0.0, sl, tp, "Stack");
   }
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
//| Lowest open price among this EA's positions                      |
//+------------------------------------------------------------------+
double LowestOpenPrice()
{
   double lowest = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      if(lowest == 0.0 || open < lowest)
         lowest = open;
   }
   return lowest;
}

//+------------------------------------------------------------------+
//| Highest open price among this EA's positions                     |
//+------------------------------------------------------------------+
double HighestOpenPrice()
{
   double highest = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      if(open > highest)
         highest = open;
   }
   return highest;
}

//+------------------------------------------------------------------+
//| Trailing stop management                                         |
//+------------------------------------------------------------------+
void ManageTrailing()
{
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

      double start = InpTrailStartPoints * _Point;
      double dist  = InpTrailStepPoints * _Point;

      if(type == POSITION_TYPE_BUY)
      {
         double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSl   = NormalizeDouble(bid - dist, _Digits);
         if(bid - open >= start && newSl > sl && newSl > open)
            trade.PositionModify(ticket, newSl, tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSl = NormalizeDouble(ask + dist, _Digits);
         if(open - ask >= start && (sl == 0.0 || newSl < sl) && newSl < open)
            trade.PositionModify(ticket, newSl, tp);
      }
   }
}
//+------------------------------------------------------------------+
