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

   uses interface List<pack> as seenPackets; //use interface to create a seen packet list for each node
   uses interface List<neighbor*> as ListOfNeighbors;
   uses interface Pool<neighbor> as PoolOfNeighbors;
   uses interface Timer<TMilli> as Timer; //uses timer to create periodic firing on neighbordiscovery and to not overload the network
   uses interface Random as Random; //randomize timing to create firing period

   uses interface Timer<TMilli> as serverTimer;

   uses interface Timer<TMilli> as clientTimer;

   uses interface List<socket_t> as sockList;
}

implementation{
   pack sendPackage;
   RoutingTable myRoutingTable;
   
   DVPack DVPacket;

   socket_t *fd;
   int transferB = 0;

   char username[SOCKET_BUFFER_SIZE];
   char bMsg[SOCKET_BUFFER_SIZE];
   char wMsg[SOCKET_BUFFER_SIZE];
   char wUser[SOCKET_BUFFER_SIZE];
   int hell = 0;
   int broad = 0;
   int mess = 0;
   int lis = 0;
   int size = 0;

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
      //Server Fire
      int x, newFd, r = 1, i;
      int oFd;
      char readBuff[SOCKET_BUFFER_SIZE];
      char writeBuff[SOCKET_BUFFER_SIZE];
      char* usern;

      dbg(TRANSPORT_CHANNEL, "Server Timer Fired\n");

      newFd = call Transport.accept(fd);
      if (newFd != NULL)
      {
	      dbg(TRANSPORT_CHANNEL, "Adding newFd : %d\n", newFd);
         call sockList.pushback(newFd);
      }
      if(call Transport.estCheck(fd) == SUCCESS) 
      {
         //Creates an empty array for buffer
         for (x = 0; x < SOCKET_BUFFER_SIZE; x++)
            readBuff[x] = 0;

         dbg(TRANSPORT_CHANNEL, "%d\n", call sockList.size());
         for (x = 0; x < call sockList.size(); x++) 
         {
            oFd = call sockList.get(x);

            dbg(TRANSPORT_CHANNEL, "reading %d\n", oFd);
  	         r = call Transport.read(oFd, readBuff, SOCKET_BUFFER_SIZE);

	         if (readBuff[0] == 104) 
            {
	            dbg(TRANSPORT_CHANNEL, "Reading Hello\n");
	            for (x = 0; x < strlen(readBuff); x++) 
               {
		            username[x] = (char) readBuff[x + 1];
 	            }
               dbg(TRANSPORT_CHANNEL, "Username: %s\n", username);
               dbg(TRANSPORT_CHANNEL, "Fd: %d\n",oFd);
	            call userMap.insert(oFd, username);
               size += strlen(readBuff);
            }
	         else if (readBuff[0] == 98) 
            {
               dbg(TRANSPORT_CHANNEL, "Reading Broadcast\n");
               for (i = 0; i < call sockList.size(); i++) 
               {
                  oFd = call sockList.get(i);
                  if (call Transport.estCheck(oFd) == SUCCESS) 
                  {
		               call Transport.write(oFd, readBuff, sizeof(readBuff));
	                  call Transport.bufCheck(oFd);
                  }
               }
               size += strlen(readBuff);
	         }
            else if (readBuff[0] == 108) 
            {			//Need to fix
               dbg(TRANSPORT_CHANNEL, "Reading Whisper\n");
               for (i = 0; i < call sockList.size(); i++) 
               {
                  oFd = call sockList.get(i);
                  if (call Transport.estCheck(oFd) == SUCCESS) 
                  {
		               call Transport.write(oFd, readBuff, sizeof(readBuff));
                     call Transport.bufCheck(oFd);
		            }
               }
               size += strlen(readBuff);
	         }
            else if (readBuff[0] == 109) 
            {
               dbg(TRANSPORT_CHANNEL, "Reading List\n");
               for (i = 0; i < call sockList.size(); i++) 
               {
                  oFd = call sockList.get(i);
                  if (call Transport.estCheck(oFd) == SUCCESS) 
                  {
		               usern = call userMap.get(oFd);
                     writeBuff[i] = usern;
                  }
	            }   
	            call Transport.write(fd, writeBuff, sizeof(writeBuff));
               call Transport.bufCheck(fd);
               size += strlen(readBuff);
	         }
            else if (r != 0) 
            {
               for (r = 0; r < SOCKET_BUFFER_SIZE; r++) 
               {
  	               if (r == SOCKET_BUFFER_SIZE - 1 && readBuff[r] != 0)		//At end with value
                     dbg(TRANSPORT_CHANNEL, "%d\n", readBuff[r]);
     	            else if (readBuff[r] != 0)				//Not at end but have value
   	               dbg(TRANSPORT_CHANNEL, "%d, \n", readBuff[r]);
	               else if (r == (SOCKET_BUFFER_SIZE - 1))			//No value and at end
                     dbg(TRANSPORT_CHANNEL, "\n");
	            }
            }
         }
      }
   }

   event void clientTimer.fired() 
   {
      //Client Fire
      int i = 0, x = 0;
      int temp = 0;
      int writeBuff[transferB];
      char readBuff[SOCKET_BUFFER_SIZE];
      char* charac;

      //New FCN to test buffer and send data accordingly
      dbg(TRANSPORT_CHANNEL, "Client Timer Fired\n");


      if (transferB != NULL) 
      {
         if (call Transport.estCheck(fd) == SUCCESS) 
         {
            for (i = 0; i < transferB; i++)
               writeBuff[i] = i + 1;

            x = call Transport.write(fd, writeBuff, transferB);

            call Transport.bufCheck(fd);
         }
         if ((transferB - x) == 0) 
         {
            call Transport.close(fd);
	         call clientTimer.stop();
         }
         else
	    transferB -= x; 
      }
      else 
      {
         if (hell == 1) 
         {
	         temp = strlen(username);
	         charac = "h";

	         call Transport.write(fd, charac, 1);
            x = call Transport.write(fd, username, strlen(username));
	         call Transport.bufCheck(fd);

	         if ((temp - x) == 0)
	            hell = 0;
	      }
	      else if (broad == 1) 
         {
            temp = strlen(bMsg);
            charac = "b";

            call Transport.write(fd, charac, 1);
            x = call Transport.write(fd, bMsg, strlen(bMsg));
            call Transport.bufCheck(fd);
            //write bMsg to buffer
            //Send msg
            if ((temp - x) == 0)
               broad = 0;	 
	      }
	      else if (mess == 1)
         {
            temp = strlen(wMsg) + strlen(wUser);
            charac = "m";

            call Transport.write(fd, charac, 1);    
            x = call Transport.write(fd, wMsg, strlen(wMsg));
            call Transport.bufCheck(fd);

            if ((temp - x) == 0)
               mess = 0;
	      }
	      else if (lis == 1) 
         {
            charac = "l";

            call Transport.write(fd, charac, 1);
            call Transport.bufCheck(fd);

            //send pckt indicating list
            lis = 0;
	      }
	      else
         {
	         dbg(TRANSPORT_CHANNEL, "Broke\n"); 		//Not actually broke

            for (x = 0; x < SOCKET_BUFFER_SIZE; x++)
               readBuff[x] = 0;

	         call Transport.read(fd, readBuff, SOCKET_BUFFER_SIZE);
	         if (readBuff[0] == 109) 
            {
	            for (x = 1; x < sizeof(readBuff); x++)
 	               wMsg[x - 1] = (char) readBuff[x];
               dbg(TRANSPORT_CHANNEL, "Whisper Message: %s\n", wMsg);
            }
            else if (readBuff[0] == 108) 
            {
               for (x = 1; x < sizeof(readBuff); x++)
                  wUser[x - 1] = (char) readBuff[x];
               dbg(TRANSPORT_CHANNEL, "List of Users: %s\n", wUser);
            }
            else if (readBuff[0] == 98) 
            {
               for (x = 1; x < sizeof(readBuff); x++)
                  bMsg[x - 1] = (char) readBuff[x];
               dbg(TRANSPORT_CHANNEL, "Broadcast Message: %s\n", bMsg);
            }
         }
      }
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
            dbg(FLOODING_CHANNEL,"Packet from %d has arrived with Msg: %s\n", myMsg->src, myMsg->payload);
             
            pushToPacketList(*myMsg); //push to seenpacketlist

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
            makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1,myMsg->protocol, myMsg->seq, (uint8_t *)myMsg->payload, sizeof(myMsg->payload));

            dbg(FLOODING_CHANNEL, "Recieved Message from %d meant for %d...Rebroadcasting\n", myMsg->src, myMsg->dest);
            pushToPacketList(sendPackage);
            call Sender.send(sendPackage, myRoutingTable.nodes[myMsg->dest].nextHop);
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


   event void CommandHandler.setTestServer()
   {
      socket_addr_t sAddr;

      dbg(TRANSPORT_CHANNEL, "Test Server Starting\n");

      sAddr.port = sPort;
      sAddr.addr = TOS_NODE_ID;

      fd = call Transport.socket();
      call Transport.bind(fd, &sAddr);
      call Transport.listen(fd);

      dbg(TRANSPORT_CHANNEL, "Starting Server Timer\n");
      call serverTimer.startPeriodic(100000);
   }

   event void CommandHandler.setTestClient()
   {
      socket_addr_t src;
      socket_addr_t dest;

      dbg(TRANSPORT_CHANNEL, "Test Client Starting\n");

      src.port = srcPort;
      src.addr = TOS_NODE_ID;
      dest.port = destPort;
      dest.addr = destination;

      fd = call Transport.socket();
      call Transport.bind(fd, &src);

      call Transport.connect(fd, &dest);
      //Connects
      call clientTimer.startPeriodic(200000);		//Client Connection
      transferB = trans;
   }

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