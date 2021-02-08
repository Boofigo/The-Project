#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"


typedef struct Neighbor
{
    uint16_t Node;
    uint8_t Age;
}   Neighbor;

module Node
{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;

   uses interface List<Neighbor*> as Neighborhood; //node creates list of node neighbors
   uses interface List<Neighbor*> as NeighborsDropped; //list of nodes removed from neighborsList
}

implementation{
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   void discoverNeighbors(); //sends out standard packet w protocol 8

   event void Boot.booted()
   {
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err)
   {
      if(err == SUCCESS)
      {
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }
      else
      {
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   //Message recieved
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
   {
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack))
      {
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload)
   {
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destination);
   }

   event void CommandHandler.findNeighbors(uint8_t *payload)
   {
      dbg(GENERAL_CHANNEL, "Discovery event \n");
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
   
   void discoverNeighbors()
   {
      dbg(NEIGHBOR_CHANNEL, "Searching for Neighbors...\n");

      //send out packet with PROTOCOL_PINGREPLY
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, MAX_TTL, PROTOCOL_PINGREPLY, -1, 0, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

}