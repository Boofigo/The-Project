interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t sPort, uint8_t window);
   event void setTestClient(int dest, int srcPort, int destPort, int trans);
   event void setAppServer(uint8_t sPort);
   event void setAppClient(uint8_t sPort);
   event void connect4(uint8_t dest, uint8_t *payload);
}
