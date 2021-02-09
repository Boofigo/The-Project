#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include <Timer.h>

typedef struct neighbor
{
    uint16_t Node;
    uint8_t Life;
}   neighbor;

module Node
{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;

   uses interface List<pack> as SeenPacketList; //use interface to create a seen packet list for each node
   uses interface List<neighbor*> as ListOfNeighbors;
   uses interface Pool<neighbor> as PoolOfNeighbors;
   uses interface Timer<TMilli> as Timer1; //uses timer to create periodic firing on neighbordiscovery and to not overload the network
}

implementation{
   pack sendPackage;
   uint16_t seqNumb = 0;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   bool findSeenPacket(pack *Package); //function for finding a packet from a node's seen packet list
   void pushToPacketList(pack Package); //push a seen packet onto a node's seen packet list
   void neighborDiscovery(); //find a nodes neighbors
   //void printNeighbors(); //print a nodes neighbor list

   event void Boot.booted()
   {
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");

      call Timer1.startPeriodicAt(1,1500);
      dbg(NEIGHBOR_CHANNEL,"Timer started\n");
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

   event void Timer1.fired()
   {
      neighborDiscovery();
   }

   //Message recieved
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
   {
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack))
      {
         pack* myMsg=(pack*) payload;
         // dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);

         if(myMsg->TTL == 0) //Time to Live is 0 so packet should be dropped
         {
           dbg(FLOODING_CHANNEL,"TTL=0:Dropping packet from %d to %d\n", myMsg->src, myMsg->dest); 
         }
         else if(findSeenPacket(myMsg))
         {//packet dropped if seen by node more than once
            dbg(FLOODING_CHANNEL,"ALREADY SEEN: Dropping packet\n"); //notify what is happening
         }
         else if(myMsg->src == TOS_NODE_ID)
         {
            dbg(FLOODING_CHANNEL,"Packet has returned to source node %d: Dropping packet\n", myMsg->src);    
         }
         else if(myMsg->dest == TOS_NODE_ID)
         {
            dbg(FLOODING_CHANNEL,"Packet from %d has arrived with Msg: %s\n", myMsg->src, myMsg->payload); //once again, notify what has happened 
             
            pushToPacketList(*myMsg); //push to seenpacketlist     
         }
         else if(AM_BROADCAST_ADDR == myMsg->dest)
         {//meant for neighbor discovery
            bool FOUND;
            uint16_t i =0, size;
            neighbor* Neighbor, *neighbor_ptr;

            switch(myMsg->protocol)
            {

               case 0: //PROTOCOL_PING
                  dbg(NEIGHBOR_CHANNEL, "NODE %d Received Protocol Ping from %d\n",TOS_NODE_ID,myMsg->src);

                  makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, 1, myMsg->seq, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
                  //dbg(NEIGHBOR_CHANNEL, "inbetween = %s\n", sendPackage.protocol);
                  pushToPacketList(sendPackage); //push to our seen list

                  call Sender.send(sendPackage, myMsg->src); //send back to sender with PINGREPLY Protocol
                  break;
                
                case 1: // PROTOCOL_PINGREPLY
                  //we got a ping reply from a neighbor so we need to update that neighbors life to 0 again because we have seen it again
                  dbg(NEIGHBOR_CHANNEL, "Recieved PINGREPLY from %d\n", myMsg->src);
                  FOUND = FALSE; //IF FOUND, we switch to TRUE
                  size = call ListOfNeighbors.size();

                  for(i = 0; i < size; i++)
                  {
                     dbg(NEIGHBOR_CHANNEL, "Error Test 1\n");
                     neighbor_ptr = call ListOfNeighbors.get(i);
                     if(neighbor_ptr->Node == myMsg->src)
                     {
                        //found neighbor in list, reset life
                        dbg(NEIGHBOR_CHANNEL, "Node %d found in neighbor list\n", myMsg->src);
                        neighbor_ptr->Life = 0;
                        FOUND = TRUE;
                        break;
                     }
                  }
                  
                  //if the neighbor is not found it means it is a new neighbor to the node and thus we must add it onto the list by calling an allocation pool for memory PoolOfNeighbors
                  if(!FOUND)
                  {
                     Neighbor = call PoolOfNeighbors.get(); //get New Neighbor
                     dbg(NEIGHBOR_CHANNEL, "Error Test 1\n");
                     Neighbor->Node = myMsg->src; //add node source
                     dbg(NEIGHBOR_CHANNEL, "Error Test 2\n");
                     Neighbor->Life = 0; //reset life
                     dbg(NEIGHBOR_CHANNEL, "Error Test 3\n");
                     call ListOfNeighbors.pushback(Neighbor); //put into list
                     dbg(NEIGHBOR_CHANNEL, "Error Test 4\n"); 
                  }
                  break;
                default:
                  break;
            }
         }
         else
         { //packet does not belong to current node
            makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));

            dbg(FLOODING_CHANNEL, "Recieved Message from %d meant for %d...Rebroadcasting\n", myMsg->src, myMsg->dest); //notify process
            pushToPacketList(sendPackage); //packet not meant for this node but we need to push into seenpacketlist
            //resend with broadcast address to move packet forward
            call Sender.send(sendPackage, AM_BROADCAST_ADDR);
         }

         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   bool findSeenPacket(pack *Package)
   {
       uint16_t packetListSize = call SeenPacketList.size();
       uint16_t i = 0;
       pack packetMatcher; //use to try to find match

       for(i = 0; i < packetListSize; i++)
       { //traverse thru SeenPacketList
           packetMatcher = call SeenPacketList.get(i);
           if(packetMatcher.src == Package->src && packetMatcher.dest == Package->dest && packetMatcher.seq == Package->seq)
           {
               return TRUE; //packet is found in SeenPacketList
           }
       }
       return FALSE; //packet not in SeenPacketList so we need to add it 
   }
   
   void pushToPacketList(pack Package)
   { 
      // dumb idea here
      call SeenPacketList.pushback(Package);
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload)
   {
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 7, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
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

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length)
   {
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
   
   void neighborDiscovery() 
   {
		pack Package;
		char* message;
		
		//dbg(NEIGHBOR_CHANNEL, "Neighbor Discovery: checking node %d list for its neighbors\n", TOS_NODE_ID);
      //makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      //call Sender.send(sendPackage, AM_BROADCAST_ADDR);

		if(!call ListOfNeighbors.isEmpty()) 
      {
		   uint16_t size = call ListOfNeighbors.size();
			uint16_t i = 0;
		   uint16_t life = 0;
		   neighbor* myNeighbor;
		   neighbor* tempNeighbor;
         dbg(NEIGHBOR_CHANNEL, "Neighbor Discovery: checking node %d list for its neighbors\n", TOS_NODE_ID);
		   //Increase Life of the ListOfNeighbors if not seen, every 5 pings a neighbor isnt seen, we are going to remove it
		   for(i = 0; i < size; i++) 
         {
				tempNeighbor = call ListOfNeighbors.get(i);
			   tempNeighbor->Life++;
		   }
		   //Check if neighbors havent been called or seen in a while, if 5 pings occur and neighbor is not hear from, we drop it
		   for(i = 0; i < size; i++) 
         {
			   tempNeighbor = call ListOfNeighbors.get(i);
			   life = tempNeighbor->Life;
			   if(life > 5) 
            {
				   myNeighbor = call ListOfNeighbors.remove(i);
				   dbg(NEIGHBOR_CHANNEL, "Node %d life has expired dropping from NODE %d list\n", myNeighbor->Node, TOS_NODE_ID);
               call PoolOfNeighbors.put(myNeighbor);
				   i--;
					size--;
				}
			}
		}

      message = "addOn\n";
		makePack(&Package, TOS_NODE_ID, AM_BROADCAST_ADDR, 2, PROTOCOL_PING, 1, (uint8_t*) message, (uint8_t) sizeof(message));

		pushToPacketList(Package);
		call Sender.send(Package, AM_BROADCAST_ADDR);

   }     
}