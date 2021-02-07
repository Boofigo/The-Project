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



   uses interface Random as Random;

	uses interface Timer<TMilli> as neighbortimer;
	uses interface Timer<TMilli> as routingtimer;
	uses interface Timer<TMilli> as TCPtimer;
	
   uses interface Hashmap<socket_store_t> as SocketsTable;
   
   uses interface Hashmap<table> as RoutingTable;
   uses interface Transport;
   
	uses interface List<Neighbor> as NeighborHood;
	uses interface Hashmap<pack> as PacketCache;



}

implementation
{
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   // Project 1 implementations (functions)
   uint16_t seqNum=0;
   uint16_t PacketSent;
   uint16_t PacketArr;
   float Q;
   bool met(uint16_t neighbor);
   bool inthemap( socket_t fd);
   void findneighbor();
   void Packhash(pack* Package, socket_t fd);
     void printNeighbors();
      socket_t getfd(TCPpack payload);
       uint16_t getfdmsg(uint16_t src);
     void ListHandler(pack *Package);
     void EstablishedSend();
     void replypackage(pack *Package);
      TCPpack dataPayload(uint16_t destport,uint16_t srcport,uint16_t flag,uint16_t ACK,uint16_t seq,uint16_t Awindow, TCPpack payload);
      TCPpack makePayload(uint16_t destport,uint16_t srcport,uint16_t flag,uint16_t ACK,uint16_t seq,uint16_t Awindow);
   void makeTCPpacket(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq,TCPpack payload, uint8_t length);
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);
   
   // end of project 1 functions 

   event void Boot.booted()
   {
      call AMControl.start();

      / a timer that will add and drop neighbors
      // the timmer will have a oneshot of (250)
      
      call neighbortimer.startOneShot(250);
      call routingtimer.startOneShot(250);

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void neighbortimer.fired(){
      findneighbor();
   }

   event void routingtimer.fired(){
      Route_flood();
   }

   event void AMControl.startDone(error_t err){
      
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


   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)
   {
      Neighbor neighbor;
      socket_store_t temp;
      socket_store_t temp2;                
      socket_t fd;
      
      table route[1];  

      if(len==sizeof(pack))
      {
         pack* myMsg=(pack*) payload;
         if(myMsg->protocol==PROTOCOL_LINKEDLIST)
         {
            memcpy(route, myMsg->payload, sizeof(route)*1);
            route[0].NextHop=myMsg->src;
            checkdest(route);
         }
            
         if(myMsg->TTL==0&&myMsg->protocol==PROTOCOL_PING)
         {
            // will drop packet when ttl expires packet will be dropped
         // dbg(ROUTING_CHANNEL, "TTL has expired, packet from %d to %d will be dropped\n",myMsg->src, myMsg->dest);
         }
            
         if(myMsg->protocol==PROTOCOL_PING)
         {
            if( TOS_NODE_ID!=myMsg->dest)
            {
            forwarding(myMsg);         
               //Packhash(myMsg);
            }
            else
            {
               dbg(ROUTING_CHANNEL, "I have recived a message from %d and it says %s\n",myMsg->src, myMsg->payload);
            }
            
            
         }  
         
         if(myMsg->protocol==PROTOCOL_TCP)
         {  
            // if ping reply add nieghbor to neighbor list && will take care of nodes being added or dropped
            if( TOS_NODE_ID!=myMsg->dest)
            {
            forwarding(myMsg);         
               //Packhash(myMsg);
            }
            else
            {
               TCPpack payload;
               memcpy(payload.payload, myMsg->payload, sizeof(payload.payload)*1);
               
               switch (payload.payload[2])
               {
                  case SYN_Flag:
                  fd = getfd(payload);
                  temp = call SocketsTable.get(fd); 
                  dbg(TRANSPORT_CHANNEL, "SERVER:I have recived a SYN_Flag from %d for Port %d\n",myMsg->src, temp.src.port);    
                  call SocketsTable.remove(fd);

                  temp.state = SYN_RCVD;
                  temp.dest.port = payload.payload[1];
                  temp.dest.addr=myMsg->src;
                  temp.effectiveWindow=payload.payload[5];
                  call SocketsTable.insert(fd, temp);
                  dbg(TRANSPORT_CHANNEL, "SERVER: Binded socket to dest addr:%d dest port: %d\n",temp.dest.addr, temp.dest.port);
                  payload = makePayload( temp.dest.port,  temp.src.port,SYN_Ack_Flag,myMsg->seq+1,myMsg->seq,0);
                  makeTCPpacket(&sendPackage, TOS_NODE_ID,myMsg->src, 3, PROTOCOL_TCP,myMsg->seq+1,payload,TCP_PACKET_MAX_PAYLOAD_SIZE );
                  Packhash(&sendPackage,fd);
                  forwarding(&sendPackage);   
                  break;
                  
                  
                  case SYN_Ack_Flag:
                  fd = getfd(payload);
                  temp = call SocketsTable.get(fd); 
                  call SocketsTable.remove(fd);
                  temp.state = ESTABLISHED;           
                  call SocketsTable.insert(fd, temp);
                  dbg(TRANSPORT_CHANNEL, "CLIENT: Connection to Server Port Established %d\n", temp.dest.port);
                  payload = makePayload( payload.payload[1],  payload.payload[0],Ack_Flag,myMsg->seq,myMsg->seq,0);
                  makeTCPpacket(&sendPackage, TOS_NODE_ID,myMsg->src, 3, PROTOCOL_TCP,myMsg->seq,payload,TCP_PACKET_MAX_PAYLOAD_SIZE ); //not complete
                  Packhash(&sendPackage,fd);
               
                  forwarding(&sendPackage);  
                  break;
               
               
                  case Ack_Flag:
                  fd = getfd(payload);
                  temp = call SocketsTable.get(fd); 
                  call SocketsTable.remove(fd);
                  temp.state = ESTABLISHED;           
                  call SocketsTable.insert(fd, temp);
                  dbg(TRANSPORT_CHANNEL, "SERVER: Connection to Client Port Established\n");
                  
                  //make a list of "ports"
                  
                  break;
               
                  default:
                  break;   
               }
            }
         } 
         
         if(myMsg->protocol==PROTOCOL_whisper)
         {                
            if( TOS_NODE_ID!=myMsg->dest)
            {              
            forwarding(myMsg);         
            //Packhash(myMsg);
            }
            if(TOS_NODE_ID==myMsg->dest)
            {
               TCPpack payload;
               uint16_t i =0,j=0;
               uint8_t A =0;
               uint16_t size = call SocketsTable.size();
               
               pack p,msg;
               
               fd = getfdmsg(myMsg->src);
               memcpy(payload.payload, myMsg->payload, sizeof( myMsg->payload)*1);
               temp = call SocketsTable.get(fd); 
      
               for(i;i<=size;i++)
               {
                  temp2 = call SocketsTable.get(i);
                  if(temp2.dest.addr==myMsg->src)
                  {
                     while(temp.user[A]!=32)
                     {
                        p.payload[A] = temp.user[A];
                        A++;
                     }
                     makePack(&sendPackage, TOS_NODE_ID, myMsg->seq, 3, PROTOCOL_Server, 0, p.payload, PACKET_MAX_PAYLOAD_SIZE);
                     forwarding(&sendPackage);
                     makePack(&sendPackage, TOS_NODE_ID, myMsg->seq, 3, PROTOCOL_Server, 7, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                     forwarding(&sendPackage);
                  }

               }
            }
         }    
         
         if(myMsg->protocol==PROTOCOL_Server)
         { 
                           
            if( TOS_NODE_ID!=myMsg->dest)
            {              
            forwarding(myMsg);         
               //Packhash(myMsg);
            }
            if(TOS_NODE_ID==myMsg->dest)
            {
               TCPpack payload;
               
               uint16_t i =0,j=0;
               uint8_t A =0;
               pack p,msg;
               
               fd = getfdmsg(myMsg->src);
               memcpy(payload.payload, myMsg->payload, sizeof( myMsg->payload)*1);
               temp = call SocketsTable.get(fd); 

               if(temp.TYPE==SERVER)
               {           
                  if (payload.payload[2] =104)
                  {
                     //sending the message to all

                     uint16_t size = call SocketsTable.size();

                     for(i;i<=size;i++)
                     {
                        temp2 = call SocketsTable.get(i);
                        if(temp2.dest.addr!=temp.dest.addr)
                        {
                           while(temp.user[A]!=32)
                           {
                              p.payload[A] = temp.user[A];
                              A++;
                           }
                           makePack(&sendPackage, TOS_NODE_ID, temp2.dest.addr, 3, PROTOCOL_Server, 0, p.payload, PACKET_MAX_PAYLOAD_SIZE);
                           forwarding(&sendPackage);
                           A=0;
                           while(j<102)
                           {
                              msg.payload[j]=myMsg->payload[6+j];
                              if(myMsg->payload[6+j]==13)
                              {
                                 j=102;
                              }
                              j++;
                           }
                                 
                           makePack(&sendPackage, TOS_NODE_ID, temp2.dest.addr, 3, PROTOCOL_Server, 104, msg.payload, PACKET_MAX_PAYLOAD_SIZE);
                           forwarding(&sendPackage);						   
                        }
                     }
                  } 
               }
               
               if(temp.TYPE==CLIENT)
               {
                  if(myMsg->seq==0)
                  {
                     dbg(TRANSPORT_CHANNEL,"Message From: %s \n", myMsg->payload);
                  }
                  else
                  {
                     dbg(TRANSPORT_CHANNEL,"Message: %s \n", myMsg->payload);
                  }
                  printf("\n");
               }
            }
         }

         if(myMsg->protocol==PROTOCOL_TCPDATA)
         { 
            if( TOS_NODE_ID!=myMsg->dest)
            {              
               forwarding(myMsg);         
               //Packhash(myMsg);
            }
            if(TOS_NODE_ID==myMsg->dest)
            {
               TCPpack payload;
               uint16_t i =0;
               uint8_t A =0;
               pack p;
               fd = getfdmsg(myMsg->src);
               memcpy(payload.payload, myMsg->payload, sizeof( myMsg->payload)*1);
               // dbg(TRANSPORT_CHANNEL, "SERVER: window %d\n ",PACKET_MAX_PAYLOAD_SIZE );
               temp = call SocketsTable.get(fd); 
               // call SocketsTable.remove(fd);
               switch (temp.TYPE)
               {
                  case SERVER:  
                  if(myMsg->payload[2]==Fin_Flag)
                  {
                     dbg(TRANSPORT_CHANNEL,"FIN FLAG for Port (%d)\n",temp.src.port );           
                     // dbg(TRANSPORT_CHANNEL,"Reading last Data for Port (%d): ", temp.src.port);
                     
                     for(i; i<myMsg->payload[5];i++)
                     {
                        // dbg(TRANSPORT_CHANNEL,"------------------------next expected %d \n",  temp.nextExpected);
                        if(myMsg->payload[3] !=104)
                        {
                           temp.rcvdBuff[i] = myMsg->payload[i+6]; //copy payload into received buffer
                        }
                        else
                        {
                           temp.user[i]=myMsg->payload[i+6];
                           //dbg(TRANSPORT_CHANNEL,"user %c\n", temp.user[i]);
                        }
                        //printf("%c,",temp.rcvdBuff[i]);
                        temp.lastRead = temp.rcvdBuff[i];
                        temp.state=ESTABLISHED;
                        // temp.nextExpected = temp.rcvdBuff[i]+1;
                        // dbg(TRANSPORT_CHANNEL,"next expected %d \n",  temp.nextExpected);
                     }
                     dbg(TRANSPORT_CHANNEL," ----------------------(%c): ....destport:.%d, fd:%d\n", temp.user[0], temp.dest.port,fd);
                     //dbg(TRANSPORT_CHANNEL,"Reading Data: ");
                     printf("\n" );
                     p.payload[0]=temp.dest.port;
                     p.payload[1]=temp.src.port;
                     p.payload[2]=Fin_Ack_Flag;
                     p.payload[3]= temp.lastRead;
                     p.payload[4]=  temp.nextExpected;
                     temp.effectiveWindow=myMsg->payload[5];
      
                     call SocketsTable.remove(fd);
                     call SocketsTable.insert(fd, temp);
                     makePack(&sendPackage, TOS_NODE_ID,myMsg->src , 3, PROTOCOL_TCPDATA, 0, p.payload, PACKET_MAX_PAYLOAD_SIZE);
                     forwarding(&sendPackage);             
                  }

                  if(myMsg->payload[2]==Data_Flag)
                  {
                     dbg(TRANSPORT_CHANNEL,"Reading Data for Port (%d): ", temp.src.port);

                     for(i; i<=temp.effectiveWindow;i++)
                     {
                        // dbg(TRANSPORT_CHANNEL,"------------------------next expected %d \n",  temp.nextExpected);
                        if( temp.nextExpected==myMsg->payload[i+6])
                        {
                           temp.rcvdBuff[i] = myMsg->payload[i+6]; //copy payload into received buffer
                           //dbg(TRANSPORT_CHANNEL,"bit %d\n",myMsg->payload[i+6]);
                           printf("%d,",temp.rcvdBuff[i]);
                           temp.lastRead = temp.rcvdBuff[i];
                           temp.nextExpected = temp.rcvdBuff[i]+1;
                           // dbg(TRANSPORT_CHANNEL,"next expected %d \n",  temp.nextExpected);
                        }
                        else
                        {
                           //	dbg(TRANSPORT_CHANNEL,"getting wrong bit%d\n",myMsg->payload[i+6]);
                           break; 
                        }
                     }
                     
                     //dbg(TRANSPORT_CHANNEL,"Reading Data: ");
                     printf("\n" );
                     p.payload[0]=temp.dest.port;
                     p.payload[1]=temp.src.port;
                     p.payload[2]=Data_Ack_Flag;
                     p.payload[3]= temp.lastRead;
                     p.payload[4]=  temp.nextExpected;
                     temp.effectiveWindow=myMsg->payload[5];
         
                     call SocketsTable.remove(fd);
                     call SocketsTable.insert(fd, temp);
                     makePack(&sendPackage, TOS_NODE_ID,myMsg->src , 3, PROTOCOL_TCPDATA, 0, p.payload, PACKET_MAX_PAYLOAD_SIZE);
                     forwarding(&sendPackage);
                     // dbg(TRANSPORT_CHANNEL,"Next bit: %d",   temp.nextExpected);
                  }       
               
                  break;
                  
                  case CLIENT:   
                  if(myMsg->payload[2]==Data_Ack_Flag)
                  {
                     fd = getfdmsg(myMsg->src);
                     temp.lastAck = myMsg->payload[3];
                     call SocketsTable.remove(fd);
                     call SocketsTable.insert(fd, temp);
                     //dbg(TRANSPORT_CHANNEL, "---------- last bit rec %d\n ",   temp.lastAck);
                     //  call TCPtimer.startOneShot(12000);
                     EstablishedSend();
                  }
                  
                  if(myMsg->payload[2]==Fin_Ack_Flag)
                  {
                     fd = getfdmsg(myMsg->src);
                     temp.lastAck = myMsg->payload[3];
                     call SocketsTable.remove(fd);
                     call SocketsTable.insert(fd, temp);
                     //	 dbg(TRANSPORT_CHANNEL, "---------- last bit rec %d\n ",   temp.lastAck);
                     //  call TCPtimer.startOneShot(12000);
                     if(temp.lastAck!=temp.Transfer_Buffer)
                     {            		 
                        //EstablishedSend();
                     }
                     else
                     {
                        dbg(TRANSPORT_CHANNEL, "ALL DATA RECIEVED\n");
                        dbg(TRANSPORT_CHANNEL, "READY TO CLOSE \n");
                        temp.state = CLOSED;
                        dbg(TRANSPORT_CHANNEL, "CLIENT CLOSED \n");
                        call SocketsTable.remove(fd);
                        call SocketsTable.insert(fd, temp);
                     }
                  }
                  break;
                  default:
                  break;
               }
               // call TCPtimer.startOneShot(12000);
               
            }
         }
      
         if(myMsg->protocol==PROTOCOL_PINGREPLY)
         {  
            // if ping reply add nieghbor to neighbor list && will take care of nodes being added or dropped
            ListHandler(myMsg);
         }   
         // This will take care of the dest node from reciving the deliverd packet again and again...
         //-------------------------------------------endofneighbordiscovery 
         return msg;
      }

      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

//-----------------------------------------------------------------------------------------------------------------------------------------
//--------------------------------------------------------------------------project 1 functions

//met will check if we already have node in neighbor list

bool met(uint16_t neighbor){
Neighbor node;
uint16_t i,size = call NeighborHood.size();   
   for(i =0; i < size;i++){
   node=call NeighborHood.get(i); 
   if(node.node==neighbor){   
        // dbg(GENERAL_CHANNEL, "We have already met dude im node: %d \n", neighbor );
   return TRUE;
   }
}
return FALSE;
}


//----------------------------------------------------------------------- ListHandler will push the nodes into a list

void ListHandler(pack* Package){
Neighbor neighbor;
if (!met(Package->src)){
localroute();
dbg(NEIGHBOR_CHANNEL, "Node %d was added to %d's Neighborhood\n", Package->src, TOS_NODE_ID);
neighbor.node = Package->src;
 call NeighborHood.pushback(neighbor);
 		PacketArr++;
   		PacketSent;
   	  localroute();	
   		 
    Q=((PacketSent)/((float)PacketArr));
   		 
   		 
   		 
   		 
   // dbg(GENERAL_CHANNEL, "Havent met you %d\n", Package->src);
 
}
}

//------------------------------------------------------------------------------------findneighbor function 
  
     void findneighbor()
     {
         Neighbor neighbor;
         char * msg;
         msg = "Help";    
         dbg(NEIGHBOR_CHANNEL, "Sending help signal to look for neighbor! \n");
         makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 2, PROTOCOL_PINGREPLY, 0, (uint8_t *)msg, (uint8_t)sizeof(msg));
         call Sender.send(sendPackage, AM_BROADCAST_ADDR);
         // neighbor.PacketSent++;
         PacketSent++;
      }
 
 //------------------------------------------------------------------------------------------------ reply message will be sent to node who sent ping

  
   void replypackage(pack* Package)
   {
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 0, PROTOCOL_PINGREPLY, 0, 0, 0);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR);
   }
//------------------------------------------------------------------------------------------------------- inthehashmap will check if node already has packet in cache
 
  
   bool inthemap(socket_t fd)
   {
      if(!call PacketCache.contains(fd))
      {
         //call PacketCache.remove(Package->src);
         dbg(FLOODING_CHANNEL, "Adding packet \n" ); 
         return FALSE;
      }
      
      if(call PacketCache.contains(fd))
      {
         //ignore help signal just add to neighborhood
         return TRUE;
      } 
   }
 //---------------------------------------------Flood will create flooding message and will send it to all neighboring nodes (this is accomplished by iterating thru neighbor list and making flooding packet)
   
   void flood(pack* Package)
   {
      Neighbor node;
      Neighbor neighbor;
	   uint16_t i,size = call NeighborHood.size(); 
      for(i =0; i < size;i++)
      {
         node=call NeighborHood.get(i); 
         if(node.node!=0&&node.node!=Package->src)
         {
            dbg(FLOODING_CHANNEL, "Flooding Packet to : %d \n", node.node );
            makePack(&sendPackage, Package->src, Package->dest, Package->TTL-1, PROTOCOL_PING, Package->seq, (uint8_t*) Package->payload, sizeof( Package->payload));
            call Sender.send(sendPackage, node.node);
    	      //dbg(FLOODING_CHANNEL, "The Packets sent %d\n", neighbor.PackSent);	
         }
      }
   }
  //-----------------------------------------------------------------------------
  // this function will push packet to our node cache(PacketCache)
   
   void Packhash(pack* Package, socket_t fd)
   {
      if(!inthemap(fd)&&Package->src==TOS_NODE_ID)
      {
         call PacketCache.insert(fd,sendPackage);
      }
      if(inthemap(fd)&&Package->src==TOS_NODE_ID)
      {
         call PacketCache.remove(fd);
         call PacketCache.insert(fd,sendPackage);
      }
   }
   
   pack getpack(socket_t fd)
   {
      pack temp;
      temp = call PacketCache.get(fd); 
      return temp;
   }
   
   // This will print our nieghbors by itterating thru the neighbor list of current node(mote)
   
   void printNeighbors()
   {
      Neighbor node;
      uint16_t i,size = call NeighborHood.size();   
      for(i =0; i < size;i++)
      {
         node=call NeighborHood.get(i); 
         if(node.node!=0)
         {
            //   dbg(GENERAL_CHANNEL, "Hello Neighbor im Node: %d \n", node.node );
         }
      }
   }

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

   event void CommandHandler.printNeighbors()
   {
      printNeighbors();
   }

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