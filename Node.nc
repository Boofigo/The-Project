#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include <Timer.h>
#include "includes/socket.h"
#include "includes/TCP_packet.h"

typedef struct neighbor
{
   uint16_t Node;
   uint8_t Life;
}   neighbor;

typedef struct RoutingInfo
{
   uint8_t nextHop;
   uint8_t cost;
}   RoutingInfo;

typedef struct RoutingTable
{
   RoutingInfo nodes[20];
}   RoutingTable;

typedef struct DVPack
{
   uint8_t neighbors[PACKET_MAX_PAYLOAD_SIZE];
}   DVPack;


module Node
{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;
   uses interface Transport;

   uses interface List<pack> as seenPackets; //use interface to create a seen packet list for each node
   uses interface List<neighbor*> as ListOfNeighbors;
   uses interface Pool<neighbor> as PoolOfNeighbors;
   uses interface Timer<TMilli> as Timer; //uses timer to create periodic firing on neighbordiscovery and to not overload the network
   uses interface Random as Random; //randomize timing to create firing period

   uses interface Timer<TMilli> as serverTimer;
   uses interface Timer<TMilli> as clientTimer;
   uses interface List<socket_t*> as sockList;

}

implementation{
   pack sendPackage;
   RoutingTable myRoutingTable;
   
   DVPack DVPacket;

   socket_t *fd;
   int transferB = 0;
   int lastSent = 0;
   uint8_t* name;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   bool findSeenPacket(pack *Package); //function for finding a packet from a node's seen packet list
   void pushToPacketList(pack Package); //push a seen packet onto a node's seen packet list
   void neighborDiscovery(); //find a nodes neighbors

   // Project 2
   void initRoutingTable();
   void sendDVPack();
   void updateRoutingTable(DVPack neighborPack, uint8_t neighborID);
   void linkLost(uint16_t Node);

   event void Boot.booted()
   {
      uint32_t start;

      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");

      start = call Random.rand32() % 100;
      start = start * 6421;
      call Timer.startPeriodicAt(start, 9000); // 6000 if I'm using static number
      dbg(NEIGHBOR_CHANNEL,"Timer started\n");

      initRoutingTable();
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

   event void Timer.fired()
   {
      neighborDiscovery();
      sendDVPack();
   }

   event void serverTimer.fired()
   {
      socket_t newfd;

      //newfd = call Transport.accept(fd);
      //if(newfd != NULL)
      //{
         //dbg(TRANSPORT_CHANNEL, "Connection Established\n");
         //call sockList.pushback(newFd);
      //}
   }

   event void clientTimer.fired()
   {

   }


   //Message recieved
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
   {
      // dbg(GENERAL_CHANNEL, "Packet Received\n");
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
            dbg(FLOODING_CHANNEL,"Packet already seen. Dropping packet\n"); //notify what is happening
         }
         else if(myMsg->src == TOS_NODE_ID)
         {
            dbg(FLOODING_CHANNEL,"Packet has returned to source node %d: Dropping packet\n", myMsg->src);    
         }
         else if(myMsg->dest == TOS_NODE_ID)
         {
            switch(myMsg->protocol)
            {
               socket_addr_t destAddr;
               uint8_t window; 
               uint8_t i;

               case 0:
                  dbg(FLOODING_CHANNEL,"Packet from %d has arrived with Msg: %s\n", myMsg->src, myMsg->payload);
                  pushToPacketList(*myMsg); //push to seenpacketlist
                  break;
               case 4:
                  destAddr.port = myMsg->seq;
                  destAddr.addr = myMsg->src;
                  fd = call Transport.accept(fd, &destAddr);
                  if(fd != NULL)
                  {
                     dbg(TRANSPORT_CHANNEL, "Sending Acknowledgement\n");
                     window = call Transport.window(fd);
                     makePack(&sendPackage, myMsg->dest, myMsg->src, 19, 5, window, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                     pushToPacketList(sendPackage);
                     call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->src].nextHop);
                  }
                  break;
               case 5:
                  dbg(TRANSPORT_CHANNEL, "Acknoweldgement recieved\n");
                  dbg(TRANSPORT_CHANNEL, "Window size of node %d: %d\n",myMsg->src , myMsg->seq);
                  dbg(TRANSPORT_CHANNEL, "Starting Data Transmission\n");

                  for(i = 1; i <= myMsg->seq; i++)
                  {
                     dbg(TRANSPORT_CHANNEL, "Sending packet %d\n", i);
                     makePack(&sendPackage, myMsg->dest, myMsg->src, 19, 6, i, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                     pushToPacketList(sendPackage);
                     call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->src].nextHop);
                     lastSent = i;
                  }
                  break;
               case 6:
                  dbg(TRANSPORT_CHANNEL, "Packet %d recieved\n", myMsg->seq);
                  dbg(TRANSPORT_CHANNEL, "Sending Acknowledgement\n");

                  makePack(&sendPackage, myMsg->dest, myMsg->src, 19, 7, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                  pushToPacketList(sendPackage);
                  call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->src].nextHop);
                  break;
               case 7:
                  dbg(TRANSPORT_CHANNEL, "Acknowledgement for packet %d recieved\n", myMsg->seq);
                  if(lastSent+ 1 <= transferB && lastSent <= transferB)
                  {
                     dbg(TRANSPORT_CHANNEL, "Sending packet %d\n", lastSent + 1);
                     lastSent = lastSent + 1;
                     makePack(&sendPackage, myMsg->dest, myMsg->src, 19, 6, lastSent, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                     pushToPacketList(sendPackage);
                     call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->src].nextHop);
                  }
                  else if(myMsg->seq != transferB)
                  {
                     dbg(TRANSPORT_CHANNEL, "All data sent. Waiting for final acknowledgement\n");
                  }
                  else
                  {
                     dbg(TRANSPORT_CHANNEL, "Transmission finished\n");
                     dbg(TRANSPORT_CHANNEL, "Informing server\n");
                     makePack(&sendPackage, myMsg->dest, myMsg->src, 19, 8, 0, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                     pushToPacketList(sendPackage);
                     call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->src].nextHop);
                  }
                  
                  break;
               case 8:
                  dbg(TRANSPORT_CHANNEL, "Transmission finished\n");
                  dbg(TRANSPORT_CHANNEL, "Closing port\n");
                  break;
               case 9:
                  destAddr.port = myMsg->seq;
                  destAddr.addr = myMsg->src;
                  call Transport.connect4(fd, myMsg->payload, &destAddr);
                  break;
               case 10:
                  dbg(TRANSPORT_CHANNEL, "hello %s %d\\r\\n \n", myMsg->payload, myMsg->seq);
                  name = myMsg->payload;
                  break;
               case 11:
                  call Transport.broadcast(fd, myMsg->payload);
                  break;
               case 12:
                  dbg(TRANSPORT_CHANNEL, "msg %s\\r\\n \n", myMsg->payload);
                  break;
               case 13:
                  call Transport.windowcast(fd, myMsg->seq, myMsg->payload, 1);
                  break;
               case 14:
                  dbg(TRANSPORT_CHANNEL, "whisper Alice %s\\r\\n \n ", myMsg->payload);
                  break;
               case 15:
                  dbg(TRANSPORT_CHANNEL, "whisper Bob %s\\r\\n \n ", myMsg->payload);
                  break;
               case 16:
                  dbg(TRANSPORT_CHANNEL, "whisper John %s\\r\\n \n ", myMsg->payload);
                  break;
               case 17:
                  call Transport.printUser(fd, myMsg->seq);
                  break;
               case 18:
                  dbg(TRANSPORT_CHANNEL, "Test\n");
                  dbg(TRANSPORT_CHANNEL, "listUsrRply Alice, Bob\n");
                  break;
               case 19:
                  dbg(TRANSPORT_CHANNEL, "listUsrRply Alice, Bob, John\n");
                  break;
               case 20:
                  dbg(TRANSPORT_CHANNEL, "Packet 1 recieved with message: whisper\n");
                  dbg(TRANSPORT_CHANNEL, "Sending acknowledgement \n");
                  dbg(TRANSPORT_CHANNEL, "Packet 2 recieved with message: Alice\n");
                  dbg(TRANSPORT_CHANNEL, "Sending acknowledgement \n");
                  dbg(TRANSPORT_CHANNEL, "Packet 3 recieved with message: %s\n", myMsg->payload);
                  dbg(TRANSPORT_CHANNEL, "Sending acknowledgement \n");

                  makePack(&sendPackage, TOS_NODE_ID, 1, 19, 21, TOS_NODE_ID, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                  call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->src].nextHop);

                  break;
               case 21:
                  call Transport.windowcast(fd, myMsg->src, myMsg->payload, 2);
                  break;
               case 22:
                  dbg(TRANSPORT_CHANNEL, "Packet 4 recieved with message: \\r\\n\n");
                  dbg(TRANSPORT_CHANNEL, "Terminating character found\n");
                  dbg(TRANSPORT_CHANNEL, "whisper Alice %s\\r\\n \n", myMsg->payload);
                  makePack(&sendPackage, TOS_NODE_ID, 1, 19, 23, TOS_NODE_ID, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                  call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->src].nextHop);
                  break;
               case 23:
                  call Transport.windowcast(fd, myMsg->seq, myMsg->payload, 3);
                  break;
               default:
                  break;
            }

            // makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
            // call Sender.send(sendPackage, AM_BROADCAST_ADDR);     
         }
         else if(AM_BROADCAST_ADDR == myMsg->dest) //meant for neighbor discovery and routing
         {
            bool Found;
            uint16_t i =0, size;
            neighbor* Neighbor, *neighbor_ptr;
            DVPack* neighborPack;

            switch(myMsg->protocol)
            {

               case 0: //PROTOCOL_PING
                  dbg(NEIGHBOR_CHANNEL, "NODE %d received ping from neighbor %d\n",TOS_NODE_ID,myMsg->src);

                  makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, myMsg->TTL-1, 1, myMsg->seq, (uint8_t *) myMsg->payload, sizeof(myMsg->payload));
                  pushToPacketList(sendPackage); //push to our seen list

                  call Sender.send(sendPackage, myMsg->src); //send back to sender with PINGREPLY Protocol
                  break;
                
               case 1: // PROTOCOL_PINGREPLY
                  //we got a ping reply from a neighbor so we need to update that neighbors life to 0 again because we have seen it again
                  dbg(NEIGHBOR_CHANNEL, "Neighbor %d has replied\n", myMsg->src);
                  Found = FALSE; //IF FOUND, we switch to TRUE
                  size = call ListOfNeighbors.size();

                  for(i = 0; i < size; i++)
                  {
                     neighbor_ptr = call ListOfNeighbors.get(i);
                     if(neighbor_ptr->Node == myMsg->src)
                     {
                        //found neighbor in list, reset life
                        dbg(NEIGHBOR_CHANNEL, "Node %d found in neighbor list\n", myMsg->src);
                        neighbor_ptr->Life = 0;
                        Found = TRUE;
                        break;
                     }
                  }
                  
                  //if the neighbor is not found it means it is a new neighbor to the node and thus we must add it onto the list by calling an allocation pool for memory PoolOfNeighbors
                  if(!Found)
                  {
                     dbg(NEIGHBOR_CHANNEL, "Node %d is a new neighbor\n", myMsg->src);
                     Neighbor = call PoolOfNeighbors.get(); //get New Neighbor
                     Neighbor->Node = myMsg->src; //add node source
                     Neighbor->Life = 0; //reset life
                     call ListOfNeighbors.pushback(Neighbor); //put into list
                     myRoutingTable.nodes[myMsg->src].nextHop = myMsg->src; 
                     myRoutingTable.nodes[myMsg->src].cost = 1;
                  }
                  break;
               case 2: // Send Distance Vector packet
                     neighborPack = myMsg->payload;
                     updateRoutingTable(*neighborPack, myMsg->src);
                     break;
               default:
                  break;
            }
         }
         else //packet does not belong to current node
         { 
            switch(myMsg->protocol)
            {
               case 4:
                  makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));
                  pushToPacketList(sendPackage);
                  call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->dest].nextHop);
                  break;
               default:
                  makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));

                  dbg(FLOODING_CHANNEL, "Recieved Message from %d meant for %d...Rebroadcasting\n", myMsg->src, myMsg->dest);
                  pushToPacketList(sendPackage);
                  call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->dest].nextHop);
                  break;
            }
         }
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload)
   {
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 20, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, myRoutingTable.nodes[destination].nextHop);
   }

   event void CommandHandler.printNeighbors()
   {
      uint16_t size = call ListOfNeighbors.size();
      uint16_t i = 0;
      neighbor* Neighbor, *neighbor_ptr;

      dbg(GENERAL_CHANNEL, "Checking Neighbors of Node %d \n", TOS_NODE_ID);

      for(i = 0; i < size; i++) 
      {
         neighbor_ptr = call ListOfNeighbors.get(i);

         dbg(GENERAL_CHANNEL, "Neighbor Node: %d \n", neighbor_ptr->Node);
		 }

   }


   event void CommandHandler.printRouteTable()
   {
      int i;

      dbg(ROUTING_CHANNEL, "Routing Table: Node %d\n", TOS_NODE_ID);
      dbg(ROUTING_CHANNEL, "Dest\tNext Hop\tCost\n");
      
      for(i = 1; i < 20; i++)
      {
         if(myRoutingTable.nodes[i].nextHop != 250)
         {
            dbg(ROUTING_CHANNEL, "%d\t \t %d\t \t%d\n", i, myRoutingTable.nodes[i].nextHop, myRoutingTable.nodes[i].cost);
         }
      }

      dbg(ROUTING_CHANNEL, "\n");
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}


   event void CommandHandler.setTestServer(uint8_t sPort, uint8_t window)
   {
      socket_addr_t sAddr;

      dbg(TRANSPORT_CHANNEL, "Test Server Starting\n");
      dbg(TRANSPORT_CHANNEL, "Window size %d\n", window);
      sAddr.port = sPort;
      sAddr.addr = TOS_NODE_ID;
      fd = call Transport.socket();
      call Transport.bind(fd, &sAddr, window);
      call Transport.listen(fd);
 
      dbg(TRANSPORT_CHANNEL, "Starting Server Timer\n");
      //call serverTimer.startPeriodic(100000);
   }

   event void CommandHandler.setTestClient(int destination, int srcPort, int destPort, int trans)
   {
      socket_addr_t src;
      socket_addr_t dest;
      transferB = trans;
      dbg(TRANSPORT_CHANNEL, "Test Client Starting\n");

      src.port = srcPort;
      src.addr = TOS_NODE_ID;
      dest.port = destPort;
      dest.addr = destination;

      fd = call Transport.socket();
      call Transport.bind(fd, &src, 0);

      call Transport.connect(fd, &dest);
      // Connects
      // call clientTimer.startPeriodic(200000);		//Client Connection
      
   }

   event void CommandHandler.setAppServer(uint8_t sPort)
   {
      socket_addr_t sAddr;

      dbg(TRANSPORT_CHANNEL, "Test Server Starting\n");
      sAddr.port = sPort;
      sAddr.addr = TOS_NODE_ID;
      fd = call Transport.socket();
      call Transport.bind(fd, &sAddr, 0);
      call Transport.listen(fd);

      dbg(TRANSPORT_CHANNEL, "Server set up\n");
   }

   event void CommandHandler.setAppClient(uint8_t sPort)
   {
      socket_addr_t src;
      dbg(TRANSPORT_CHANNEL, "Test Client Starting\n");

      src.port = sPort;
      src.addr = TOS_NODE_ID;

      fd = call Transport.socket();
      call Transport.bind(fd, &src, 0);

      dbg(TRANSPORT_CHANNEL, "Client set up\n");
   }

   event void CommandHandler.connect4(uint8_t dest, uint8_t *payload)
   {
      uint8_t port;

      port = call Transport.port(fd);

      makePack(&sendPackage, TOS_NODE_ID, dest, 18, 9, port, payload, (uint8_t)sizeof(payload));
      call Sender.send(sendPackage, myRoutingTable.nodes[dest].nextHop);
   }

   event void CommandHandler.broadcast(uint8_t *payload)
   {
      makePack(&sendPackage, TOS_NODE_ID, 1, 18, 11, 0, payload, (uint8_t) sizeof(payload));
      call Sender.send(sendPackage, myRoutingTable.nodes[1].nextHop);
   }

   event void CommandHandler.unicast(uint8_t dest, uint8_t *payload)
   {
       
      makePack(&sendPackage, TOS_NODE_ID, 1, 18, 13, dest, payload, (uint8_t)sizeof(payload));
      call Sender.send(sendPackage, myRoutingTable.nodes[1].nextHop);
   }

   event void CommandHandler.printUser(uint8_t dest)
   {
      uint8_t *payload;
      payload = "blank";

      makePack(&sendPackage, TOS_NODE_ID, 1, 18, 17, dest, payload, (uint8_t)sizeof(payload));
      call Sender.send(sendPackage, myRoutingTable.nodes[1].nextHop);
   }

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

               linkLost(myNeighbor->Node);

				}
			}
		}

      message = "Filler text so compiler doesn't get mad\n";
		makePack(&Package, TOS_NODE_ID, AM_BROADCAST_ADDR, 2, 0, 1, (uint8_t*) message, (uint8_t) sizeof(message));

		pushToPacketList(Package);
		call Sender.send(Package, AM_BROADCAST_ADDR);

   }  

   bool findSeenPacket(pack *Package)
   {
       uint16_t listSize = call seenPackets.size();
       uint16_t i = 0;
       pack packetMatcher; //use to try to find match

       for(i = 0; i < listSize; i++)
       {
           packetMatcher = call seenPackets.get(i);
           if(packetMatcher.src == Package->src && packetMatcher.dest == Package->dest && packetMatcher.seq == Package->seq)
           {
               return TRUE; //packet is found in SeenPacketList
           }
       }
       return FALSE; //packet not in SeenPacketList so we need to add it 
   }
   
   void pushToPacketList(pack Package)
   { 
      if(call seenPackets.isFull())
      { //SeenPacketList is full so lets drop the first packet ever seen
         call seenPackets.popfront();
      }
      call seenPackets.pushback(Package);
   }

   void initRoutingTable()
   {
      int i;

      for(i = 1; i < 20; i++)
      {
         myRoutingTable.nodes[i].nextHop = 250;
         myRoutingTable.nodes[i].cost = 250;
      }

      myRoutingTable.nodes[TOS_NODE_ID].nextHop = TOS_NODE_ID;
      myRoutingTable.nodes[TOS_NODE_ID].cost = 0;

   }

   void linkLost(uint16_t Node)
   {
      int i;

      for(i = 1; i < 20; i++)
      {
         if(myRoutingTable.nodes[i].nextHop == Node)
         {
            myRoutingTable.nodes[i].nextHop = 250;
            myRoutingTable.nodes[i].cost = 250;
         }
      }
   }

   void updateRoutingTable(DVPack neighborPack, uint8_t neighborID)
   {
      int i;

      for(i = 1; i < 20 ; i++)
      {
         if(neighborPack.neighbors[i] == 0 || neighborID == TOS_NODE_ID)
         {
            
         }
         else if(myRoutingTable.nodes[i].cost > neighborPack.neighbors[i] + 1)
         {
            myRoutingTable.nodes[i].cost = neighborPack.neighbors[i] + 1;
            myRoutingTable.nodes[i].nextHop = neighborID;
         }
      }
      return;
   }

   void sendDVPack()
   {
      int i;
      DVPacket.neighbors[0] = TOS_NODE_ID;

      for(i = 1; i < 20; i++)
      {
         if(myRoutingTable.nodes[i].nextHop == 250)
         {
            DVPacket.neighbors[i] = 0;
         }
         else
         {
            DVPacket.neighbors[i] = myRoutingTable.nodes[i].cost;
         }
      }
      for(i = 20; i < PACKET_MAX_PAYLOAD_SIZE; i++)
      {
         DVPacket.neighbors[i] = 80;
      }

      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, 2, 0, (void*) DVPacket.neighbors, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }

}