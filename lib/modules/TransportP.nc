#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/TCP_packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"
#include <stdlib.h>
#include <Timer.h>

typedef struct ClientInfo
{
   uint8_t src;
   uint8_t port;
   char* name;
}   ClientInfo;

typedef struct ClientTable
{
   ClientInfo clients[20];
}   ClientTable;

module TransportP {
   provides interface Transport;

   uses interface Hashmap<socket_store_t> as sMap;
   uses interface List<int> as sList;
   uses interface List<int> as estList;

   uses interface Timer<TMilli> as closeTimer;
   uses interface SimpleSend as TransportSender;

   uses interface Hashmap<socket_store_t> as SocketsTable;

}

implementation {

   ClientTable myClientTable;
   pack sendPackage;

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);



   event void closeTimer.fired() {
      // delete
   }

   command socket_t Transport.socket()
   {
      int i;
      int found = 0;
      socket_t fd;
      socket_store_t socket;
      
      for (i = 1; i < MAX_NUM_OF_SOCKETS; i++) 
      {
         if(!call SocketsTable.contains(i)) 
         {
            fd = i;
            dbg(TRANSPORT_CHANNEL,"Socket %d allocated\n", fd);
            call SocketsTable.insert(fd, socket);
            found = 1;
            break;
         }
      }
      if(found == 0)
      {
         dbg(TRANSPORT_CHANNEL, "No Available Socket: return NULL\n");
         fd = NULL;
      }
      return fd;
   }

   command error_t Transport.bind(socket_t fd, socket_addr_t *addr, uint8_t window) 
   {
      socket_store_t temp;
      uint8_t i =1;

      if(call SocketsTable.isEmpty())
      {
         dbg(TRANSPORT_CHANNEL, "Fail\n");
         return FAIL;
      }
      for(i;i<=MAX_NUM_OF_SOCKETS;i++)
      {
         if(i == fd)
         {
            temp = call SocketsTable.get(i);
            call SocketsTable.remove(i);

            temp.src = addr->port;
            temp.effectiveWindow = window;

            call SocketsTable.insert(i, temp);
            dbg(TRANSPORT_CHANNEL, "Socket successfully bound\n");
            return  TRUE;     
         }  
      }

      //dbg(TRANSPORT_CHANNEL, "Fail\n");
      return  FAIL;     
   }

   command socket_t Transport.accept(socket_t fd, socket_addr_t *addr)
   {
      socket_store_t temp;
      uint8_t i = 1;

      dbg(TRANSPORT_CHANNEL, "Request from node %d to send recieved on port %d\n", addr->addr, addr->port );
      if(call SocketsTable.isEmpty())
      {
         dbg(TRANSPORT_CHANNEL, "Fail\n");
         return NULL;
      }
      for(i;i<=MAX_NUM_OF_SOCKETS;i++)
      {
         if(i == fd)
         {
            temp = call SocketsTable.get(i);
            call SocketsTable.remove(i);

            temp.dest.port = addr->port;
            temp.dest.addr = addr->addr;

            call SocketsTable.insert(i, temp);
            dbg(TRANSPORT_CHANNEL, "Accepting socket\n");
            return  fd;     
         }  
      }
      return NULL;
      // test
   }

   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen)
   {
      // test
   }

   command error_t Transport.receive(pack* package)
   {
      dbg(TRANSPORT_CHANNEL, "Test 2\n");
      return FAIL;
      // test
   }

   command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen)
   {
      // test

   }

   command error_t Transport.connect(socket_t fd, socket_addr_t * addr)
   {
      int i = 1;
      char* message;
      message = "SO it doesn't hate";

      makePack(&sendPackage, TOS_NODE_ID, addr->addr, 2, 4, addr->port, (uint8_t*) message, (uint8_t) sizeof(message));

      if(TOS_NODE_ID < addr->addr)
      {
         call TransportSender.send(sendPackage, TOS_NODE_ID + 1 ); // fix this for routing
      }
      else if(TOS_NODE_ID > addr->addr)
      {
         call TransportSender.send(sendPackage, TOS_NODE_ID - 1 ); // fix this for routing
      }
      
      dbg(TRANSPORT_CHANNEL, "Sending request to send data to node %d\n", addr->addr);
      return TRUE;
   }

   command error_t Transport.close(socket_t fd)
   {
      // test

   }

   command error_t Transport.release(socket_t fd)
   {
      // test
   }

   command error_t Transport.listen(socket_t fd) 
   {
      socket_store_t temp;
      uint8_t i = 0;
      uint8_t j = 0;
      if(call SocketsTable.isEmpty())
      {
         // dbg(TRANSPORT_CHANNEL, "Fail\n");
         return FAIL;
      }

      for(j = 0; j < 20; j++)
      {
         myClientTable.clients[j].src = 250;
         myClientTable.clients[j].port = 250;
      }

      for(i;i<=MAX_NUM_OF_SOCKETS;i++)
      {
         if(i ==fd)
         {
            temp = call SocketsTable.get(i);
            call SocketsTable.remove(i);

            temp.state =LISTEN;

            dbg(TRANSPORT_CHANNEL,"Changed state to Listen!\n");

            call SocketsTable.insert(i,temp);
            // dbg(TRANSPORT_CHANNEL, "True\n");
            return SUCCESS;
         }
      }

      // dbg(TRANSPORT_CHANNEL, "Fail\n");
      return FAIL;
  
   }

   command uint8_t Transport.window(socket_t fd)
   {
      socket_store_t temp;
      temp = call SocketsTable.get(fd);

      return temp.effectiveWindow;
   }

   command uint8_t Transport.port(socket_t fd)
   {
      socket_store_t temp;
      temp = call SocketsTable.get(fd);

      return temp.src;
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

   command error_t Transport.connect4(socket_t fd, uint8_t *payload, socket_addr_t *addr)
   {
      socket_store_t temp;

      myClientTable.clients[addr->addr].src = addr->addr;
      myClientTable.clients[addr->addr].port = addr->port;
      myClientTable.clients[addr->addr].name = payload;
      
      makePack(&sendPackage, TOS_NODE_ID, addr->addr, 18, 10, addr->port, payload, (uint8_t) sizeof(payload));
      call TransportSender.send(sendPackage, 2);
      
      return NULL;
      // test


   }

   command error_t Transport.unicast(socket_t fd, uint8_t dest, uint8_t *payload)
   {
      char* message;
      message = myClientTable.clients[dest].name;
      dbg(TRANSPORT_CHANNEL, "%s\n", *message);

      makePack(&sendPackage, TOS_NODE_ID, dest, 18, 14, 0, payload, (uint8_t) sizeof(payload));
      call TransportSender.send(sendPackage, 2);

      makePack(&sendPackage, TOS_NODE_ID, dest, 18, 15, 0, message, (uint8_t) sizeof(message));
      call TransportSender.send(sendPackage, 2);

      makePack(&sendPackage, TOS_NODE_ID, dest, 18, 15, 0, payload, (uint8_t) sizeof(payload));
      call TransportSender.send(sendPackage, 2);

      makePack(&sendPackage, TOS_NODE_ID, dest, 18, 16, 0, payload, (uint8_t) sizeof(payload));
      call TransportSender.send(sendPackage, 2);
   }

   command error_t Transport.broadcast(socket_t fd, uint8_t *payload)
   {
      uint8_t i = 0;

      for(i = 0; i < 20; i++)
      {
         if(myClientTable.clients[i].src != 250)
         {
            makePack(&sendPackage, TOS_NODE_ID, i, 18, 12, 0, payload, (uint8_t) sizeof(payload));
            call TransportSender.send(sendPackage, 2);
         }
      }

      
   }

   command error_t Transport.printUser(socket_t fd)
   {
      
   }

   

}