/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/TCP_packet.h"
#include "includes/socket.h"


typedef struct{

uint16_t node;

} Neighbor;


module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;



   //uses interface Random as Random;

	//uses interface Timer<TMilli> as neighbortimer;
	//uses interface Timer<TMilli> as routingtimer;
	//uses interface Timer<TMilli> as TCPtimer;
	
   //uses interface Hashmap<socket_store_t> as SocketsTable;
   
   //uses interface Hashmap<table> as RoutingTable;
   //uses interface Transport;
   
	//uses interface List<Neighbor> as NeighborHood;
	//uses interface Hashmap<pack> as PacketCache;



}

implementation
{
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   // Project 1 implementations (functions)
   //uint16_t seqNum=0;
   //uint16_t PacketSent;
   //uint16_t PacketArr;
   //float Q;
   //bool met(uint16_t neighbor);
   //bool inthemap( socket_t fd);
   //void findneighbor();
   //void Packhash(pack* Package, socket_t fd);
     //void printNeighbors();
      //socket_t getfd(TCPpack payload);
       //uint16_t getfdmsg(uint16_t src);
     //void ListHandler(pack *Package);
     //void EstablishedSend();
     //void replypackage(pack *Package);
      //TCPpack dataPayload(uint16_t destport,uint16_t srcport,uint16_t flag,uint16_t ACK,uint16_t seq,uint16_t Awindow, TCPpack payload);
      //TCPpack makePayload(uint16_t destport,uint16_t srcport,uint16_t flag,uint16_t ACK,uint16_t seq,uint16_t Awindow);
   //void makeTCPpacket(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq,TCPpack payload, uint8_t length);
   //void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   
   // end of project 1 functions 

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 0, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, destination);
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
}