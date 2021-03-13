//Trasnport wire

configuration TransportC{
   provides interface Transport;
}
implementation{
   components TransportP;
   Transport = TransportP;

   components new HashmapC (socket_store_t, 64) as sMapC;
   TransportP.sMap -> sMapC;

   components new HashmapC (socket_store_t, 64) as SocketsTable;
   TransportP.sMap -> SocketsTable;

   components new ListC (int, 64) as sListC;
   TransportP.sList -> sListC;

   components new ListC (int, 64) as estListC;
   TransportP.estList -> estListC;

   components new TimerMilliC() as closeTimer;
   TransportP.closeTimer -> closeTimer;


   components new SimpleSendC(AM_PACK);
   TransportP.TransportSender -> SimpleSendC;
}