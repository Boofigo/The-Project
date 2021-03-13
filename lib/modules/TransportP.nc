#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/TCP.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"
#include <stdlib.h>
#include <Timer.h>

module TransportP {
   provides interface Transport;

   uses interface Hashmap<socket_store_t> as sMap;
   uses interface List<int> as sList;
   uses interface List<int> as estList;

   uses interface Timer<TMilli> as closeTimer;
   uses interface SimpleSend as TransportSender;
}

implementation {

   socket_store_t socket;  

   event void closeTimer.fired() {
      if (socket.state == TIME_WAIT) 
      {
	      socket.state = CLOSED;
         dbg(TRANSPORT_CHANNEL, "%d IS NOW CLOSED WITH PORT %d\n", TOS_NODE_ID, socket.src.port);
         dbg(TRANSPORT_CHANNEL, "CLOSED BABY!!!!\n");
      }
      call closeTimer.stop();
   }

   command socket_t Transport.socket()
   {
      int x, i;
      int fd = 255;

      dbg(TRANSPORT_CHANNEL, "Reached socket\n");

      for (i = 0; i < MAX_NUM_OF_SOCKETS; i++) 
      {
	      if(!call sMap.contains(i)) 
         {
	         socket.flag = 0;
      	   socket.state = CLOSED;
      	   socket.src.port = 0;
	         socket.src.addr = 0;
  	         socket.dest.port = 0;
	         socket.dest.addr = 0;
  	         socket.lastWritten = 0;
   	      socket.lastAck = 0;
  	         socket.lastSent = 0;
     	      for (x = 0; x < SOCKET_BUFFER_SIZE; x++)
            {
               socket.rcvdBuff[x] = 0;
               socket.sendBuff[x] = 0;
            }
            socket.lastRead = 0;
            socket.lastRcvd = 0;
      	   socket.nextExpected = 0;
   	      socket.RTT = 0;
  	         socket.effectiveWindow = 0;
	         break;
	      }
      }

      fd = i;
      call sMap.insert(fd, socket);

      return fd;
   }

   command error_t Transport.bind(socket_t fd, socket_addr_t *addr) 
   {
      dbg(TRANSPORT_CHANNEL, "Binding\n");
      socket = call sMap.get(fd);

      socket.src.port = addr->port;
      socket.src.addr = addr->addr;

      call sMap.insert(fd, socket);

      return SUCCESS;
   }

   command socket_t Transport.accept(socket_t fd) 
   {
      int i, a = 0;

      dbg(TRANSPORT_CHANNEL, "Accepted\n");

      for (i = 0; i < call sList.size(); i++) 
      {
         if (fd == call sList.get(i))
	      a = 1;
      }
      if (a == 0) 
      {
	      dbg(TRANSPORT_CHANNEL, "%d has been accpeted\n", fd); //Places fd in a List of accepted sockets
         call sList.pushback(fd);
	      return fd;
      }
      else
      {
         return NULL;
      }
	      
   }

   command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) 
   {	//Client side ONLY
      int x, writeLN = 0;
      int loop = 0;     //Loop around whole buffer = 1  ----- Doesnt loop mean = 0
      int i;

      dbg(TRANSPORT_CHANNEL, "Writing\n");

      if (call sMap.contains(fd)) {
         socket = call sMap.get(fd);
      }
      else {
         dbg(TRANSPORT_CHANNEL, "Shit broke yo\n Error in write list\n");
         return 0;      //ERROR
      }

      if (socket.lastAck <= socket.lastWritten) {
	   dbg(TRANSPORT_CHANNEL, "Something to write\n"); //Loops around in buffer
	   writeLN = (SOCKET_BUFFER_SIZE - socket.lastWritten + socket.lastAck);
	   loop = 1;
      }
      else {
	   //Doesn't loop around still has buffer to fill
	   writeLN = socket.lastAck - socket.lastWritten;
      }

      if (bufflen > writeLN) {
	   //For when have writeLN space and bufflen is larger than can write
	   dbg(TRANSPORT_CHANNEL, "Not enough room to write Have: %d and Need: %d\n", writeLN, bufflen);
	   return 0;
      }
      else {
	   if (loop == 1) {
	    dbg(TRANSPORT_CHANNEL, "It loops\n");
	    x = SOCKET_BUFFER_SIZE - socket.lastWritten;
	    if (bufflen > x) {
	       memcpy(socket.sendBuff + socket.lastWritten, buff, x*sizeof(uint8_t));
	       memcpy(socket.sendBuff, buff + x, (bufflen - x)*sizeof(uint8_t));
	    }
	    else
	       dbg(TRANSPORT_CHANNEL, "should get here\n");
               memcpy(socket.sendBuff + socket.lastWritten, buff, bufflen*sizeof(uint8_t));

	    if (writeLN < (SOCKET_BUFFER_SIZE - socket.lastWritten) || bufflen < x) {
	       socket.lastWritten += bufflen;
               dbg(TRANSPORT_CHANNEL, "Maybe here \n");
	    }
	    else {
               dbg(TRANSPORT_CHANNEL, "Then here\n");
               socket.lastWritten = bufflen - x;
	    }
         }
	   else {
 	    dbg(TRANSPORT_CHANNEL, "Doesnt loop\n");
            memcpy(socket.sendBuff + socket.lastWritten, buff, bufflen*sizeof(uint8_t));
	    socket.lastWritten += bufflen;
	   }
	   if (socket.lastWritten > SOCKET_BUFFER_SIZE) {
            socket.lastWritten -= SOCKET_BUFFER_SIZE;
	   }

         //	 for(i = 0; i < 20; i++)
      //         dbg(TRANSPORT_CHANNEL, "%d\n",socket.sendBuff[i]);

	 dbg(TRANSPORT_CHANNEL, "Written to buffer %d\n", socket.lastWritten);
	 call sMap.insert(fd, socket);

	 return bufflen;
      }
   }

   command error_t Transport.receive(pack* package) 
   {
      int srcPort, destPort, seq, ack, flag, adWindow, x, rcvdLN, z, fd;
      int loop = 0;     //Loop around whole buffer = 1  ----- Doesnt loop mean = 0
      int msgBuf[TCP_MAX_PAYLOAD_SIZE];
      int bufflen = TCP_MAX_PAYLOAD_SIZE;
      pack regPack;
      tcpPack* tcpPacket;
      socket_addr_t tempS, tempD;
      char* array;
      int i;

      tcpPack *myMsg = (tcpPack*) package->payload;

      dbg(TRANSPORT_CHANNEL, "Receiving\n");

      srcPort = myMsg->srcPort;			//vv  Quality of life  vv
      destPort = myMsg->destPort;
      seq = myMsg->seq;
      ack = myMsg->ack;
      flag = myMsg->flag;			//^^  Quality of life  ^^

      if (flag == 0 || flag == 1 || flag == 2) 
      {
         if (flag == 0) 
         {
	         dbg(TRANSPORT_CHANNEL, "Recieved SYN\n");

            tempS.addr = TOS_NODE_ID;
            tempS.port = destPort;
            tempD.addr = 0;
            tempD.port = 0;
            fd = call Transport.find(&tempS, &tempD);

            if (call sMap.contains(fd))
               socket = call sMap.get(fd);

            if (socket.state !=SYN_RCVD) 
            {
	          //Checks if the server is currently listening

	            if (call sMap.contains(fd))
	          socket = call sMap.get(fd);
               socket.state = SYN_RCVD;
               socket.dest.port = srcPort;
               socket.dest.addr = package->src;

               tcpPacket = (tcpPack*) regPack.payload;
               tcpPacket->srcPort = socket.src.port;
               tcpPacket->destPort = socket.dest.port;
               tcpPacket->seq = seq + 1;
               tcpPacket->ack = seq + 1;
               tcpPacket->flag = 2;
               tcpPacket->adWindow = SOCKET_BUFFER_SIZE;

               call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

               dbg(TRANSPORT_CHANNEL, "SYN-ACK being sent to %d from %d\n", socket.dest.addr, socket.src.addr);

	            call sMap.insert(fd, socket);
               call TransportSender.send(regPack, AM_BROADCAST_ADDR);
	         }
            else {
               dbg(TRANSPORT_CHANNEL, "Resending SYN-ACK\n");

               tcpPacket = (tcpPack*) regPack.payload;
               tcpPacket->srcPort = socket.src.port;
               tcpPacket->destPort = socket.dest.port;
               tcpPacket->seq = seq + 1;
               tcpPacket->ack = seq + 1;
               tcpPacket->flag = 2;
               tcpPacket->adWindow = SOCKET_BUFFER_SIZE;

               call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

               dbg(TRANSPORT_CHANNEL, "SYN-ACK being sent to %d from %d\n", socket.dest.addr, socket.src.addr);

               call TransportSender.send(regPack, AM_BROADCAST_ADDR);
            }
 	      }
         else if (flag == 1) 
         {
	         //Got the ACK flag meaning that connection should be completly established
            dbg(TRANSPORT_CHANNEL, "Recieved ACK\n");

            tempS.addr = TOS_NODE_ID;
            tempS.port = destPort;
            tempD.addr = package->src;
            tempD.port = srcPort;
            fd = call Transport.find(&tempS, &tempD);

            if(call sMap.contains(fd))
               socket = call sMap.get(fd);

	         if (socket.state == SYN_RCVD) 
            {		//SYN had been recieved
	            socket.state = ESTABLISHED;
	            socket.effectiveWindow = myMsg->adWindow;

               dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED - %d with port %d\n", TOS_NODE_ID, socket.src.port);

	            call estList.pushback(fd);
	            call sMap.insert(fd, socket);
	         }
         }
	      else 
         {					//flag should equal 2 here (SYN-ACK)
	         dbg(TRANSPORT_CHANNEL, "Recieved SYN-ACK\n");

            tempS.addr = TOS_NODE_ID;
            tempS.port = destPort;
            tempD.addr = package->src;
            tempD.port = srcPort;
            fd = call Transport.find(&tempS, &tempD);
	         socket = call sMap.get(fd);

	         if (socket.state == SYN_SENT) 
            {
	            //This socket sent the SYN got the SYN-ACK now completing the three way handshake
	            dbg(TRANSPORT_CHANNEL, "Sending ACK\n");

	            tcpPacket = (tcpPack*) regPack.payload;
               tcpPacket->srcPort = socket.src.port;
               tcpPacket->destPort = socket.dest.port;
               tcpPacket->seq = seq + 1;
               tcpPacket->ack = seq + 1;
               tcpPacket->flag = 1;		//ACK flag
               tcpPacket->adWindow = SOCKET_BUFFER_SIZE;

               call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

               dbg(TRANSPORT_CHANNEL, "ACK being sent to %d from %d\n", socket.dest.addr, socket.src.addr);

               call TransportSender.send(regPack, AM_BROADCAST_ADDR);

	            socket.state = ESTABLISHED;
	            socket.effectiveWindow = myMsg->adWindow;

	            dbg(TRANSPORT_CHANNEL, "CONNECTION ESTABLISHED - %d with port %d\n", TOS_NODE_ID, socket.src.port);

	            call estList.pushback(fd);
	            call sMap.insert(fd, socket);
	         }
	         else if (socket.state == ESTABLISHED) 
            {
	            //Destination never got the ACK Q_Q
	            dbg(TRANSPORT_CHANNEL, "Resending ACK\n");
	       
               tcpPacket = (tcpPack*) regPack.payload;
               tcpPacket->srcPort = socket.src.port;
               tcpPacket->destPort = socket.dest.port;
               tcpPacket->seq = seq + 1;
               tcpPacket->ack = seq + 1;
               tcpPacket->flag = 1;             //ACK flag
               tcpPacket->adWindow = SOCKET_BUFFER_SIZE;

               call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

               dbg(TRANSPORT_CHANNEL, "ACK being sent to %d from %d\n", socket.dest.addr, socket.src.addr);

               call TransportSender.send(regPack, AM_BROADCAST_ADDR);
            }
	      }
      }
      else if (flag == 3 || flag == 4) 
      {
         dbg(TRANSPORT_CHANNEL, "Closing Flag\n");
	      //DATA
         if (flag == 3) 
         {
	         tempS.addr = TOS_NODE_ID;
            tempS.port = srcPort;
            tempD.addr = package->src;
            tempD.port = destPort;
            fd = call Transport.find(&tempS, &tempD);
            // dbg(TRANSPORT_CHANNEL, "%d\n", fd);
            if (fd == 231) 
            {
               dbg(TRANSPORT_CHANNEL, "fd Not Found Trying Other Values\n");
               tempS.addr = TOS_NODE_ID;
               tempS.port = destPort;
               tempD.addr = package->src;
               tempD.port = srcPort;
               fd = call Transport.find(&tempS, &tempD);
               if (fd == 231)
                  dbg(TRANSPORT_CHANNEL, "REEEEEEEEEEEEEEEEEEEEE IT BROKE REEEEEEEEEEEE!!!!\n");
            }
            socket = call sMap.get(fd);

            if (socket.state == ESTABLISHED) 
            {
               socket.state = CLOSE_WAIT;
               dbg(TRANSPORT_CHANNEL, "Current Socket State: %d\n", socket.state);
            }
 
            tcpPacket = (tcpPack*) regPack.payload;
            tcpPacket->srcPort = socket.src.port;
            tcpPacket->destPort = socket.dest.port;
            tcpPacket->seq = seq + 1;
            tcpPacket->ack = seq + 1;
            tcpPacket->flag = 4;             //FIN ACK flag
            tcpPacket->adWindow = SOCKET_BUFFER_SIZE;

            call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

            dbg(TRANSPORT_CHANNEL, "FIN ACK being sent to %d from %d\n", socket.dest.addr, socket.src.addr);
  
            call TransportSender.send(regPack, AM_BROADCAST_ADDR);

            if (socket.state == CLOSE_WAIT) 
            {
               socket.state = LAST_ACK;
               dbg(TRANSPORT_CHANNEL, "Current Socket State: %d\n", socket.state);

               tcpPacket = (tcpPack*) regPack.payload;
               tcpPacket->srcPort = socket.src.port;
               tcpPacket->destPort = socket.dest.port;
               tcpPacket->seq = seq + 2;
               tcpPacket->ack = seq + 2;
               tcpPacket->flag = 3;             //FIN flag
               tcpPacket->adWindow = SOCKET_BUFFER_SIZE;

               call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

               dbg(TRANSPORT_CHANNEL, "FIN being sent to %d from %d\n", socket.dest.addr, socket.src.addr);

               call TransportSender.send(regPack, AM_BROADCAST_ADDR);
            }
            else if (socket.state == FIN_WAIT_2) 
            {
               socket.state = TIME_WAIT;
               dbg(TRANSPORT_CHANNEL, "Current Socket State: %d\n", socket.state);
               call closeTimer.startOneShot(1200);
            }  

	         call sMap.insert(fd, socket);
         }
	      //FIN-ACK
	      else if (flag == 4) 
         {
            tempS.addr = TOS_NODE_ID;
            tempS.port = srcPort;
            tempD.addr = package->src;
            tempD.port = destPort;
            fd = call Transport.find(&tempS, &tempD);
            if (fd == 231) 
            {
               dbg(TRANSPORT_CHANNEL, "fd Not Found Trying Other Values\n");
               tempS.addr = TOS_NODE_ID;
               tempS.port = destPort;
               tempD.addr = package->src;
               tempD.port = srcPort;
               fd = call Transport.find(&tempS, &tempD);
	            if (fd == 231)
                  dbg(TRANSPORT_CHANNEL, "REEEEEEEEEEE IT BROKE REEEEEEEEEE\n");
            }
            socket = call sMap.get(fd);

            if (socket.state == FIN_WAIT_1) 
            {
 	            socket.state = FIN_WAIT_2;
               dbg(TRANSPORT_CHANNEL, "Current Socket State: %d\n", socket.state);   
            }
            else if (socket.state == LAST_ACK) 
            {
               socket.state = CLOSED;
	            dbg(TRANSPORT_CHANNEL, "%d IS NOW CLOSED WITH PORT %d\n", TOS_NODE_ID, socket.src.port);
            }
            call sMap.insert(fd, socket);
         }
      }
      else 
      {
         //Data Payloads 
         tempS.addr = TOS_NODE_ID;
         tempS.port = srcPort;
         tempD.addr = package->src;
         tempD.port = destPort;
         fd = call Transport.find(&tempS, &tempD);
         if (fd == 231) 
         {
            dbg(TRANSPORT_CHANNEL, "fd Not Found Trying Other Values\n");
            tempS.addr = TOS_NODE_ID;
            tempS.port = destPort;
            tempD.addr = package->src;
            tempD.port = srcPort;
            fd = call Transport.find(&tempS, &tempD);
            if (fd == 231)
               dbg(TRANSPORT_CHANNEL, "REEEEEEEEEEE IT BROKE REEEEEEEEEE\n");
         }

         if (flag == 6) 
         {
	         //Data ACK
	         dbg(TRANSPORT_CHANNEL, "Recieved DATA-ACK\n");
	         socket.lastAck = (ack * TCP_MAX_PAYLOAD_SIZE);

      	   //Checks if goes over the buffer
	         if (socket.lastAck > SOCKET_BUFFER_SIZE)
	            socket.lastAck -= SOCKET_BUFFER_SIZE;
	         call sMap.insert(fd, socket);
	         dbg(TRANSPORT_CHANNEL, "EZ\n");
         }
	      else 
         {
	         //Data
	         dbg(TRANSPORT_CHANNEL, "Recieved DATA\n");

	         z = SOCKET_BUFFER_SIZE - socket.lastRcvd;

	         // dbg(TRANSPORT_CHANNEL, "%d, %d\n", socket.dest.addr, socket.state);

	         //Finds bufflen from the paylaod
	         for (x = 0; x < TCP_MAX_PAYLOAD_SIZE; x++) 
            {
	            if (myMsg->payload[x] == 0) 
               {
                  bufflen = x;
		            break;
	            }
            }
            dbg(TRANSPORT_CHANNEL, "bufflen : %d\n", bufflen);

	         if (socket.lastRcvd >= socket.lastRead) 
            { 
	            rcvdLN = (SOCKET_BUFFER_SIZE - socket.lastRcvd) + socket.lastRead;
	            loop = 1;	//It looped around buffer
	            dbg(TRANSPORT_CHANNEL, "Loops!\n");
	         }
	         else 
            {
	            rcvdLN = socket.lastRead - socket.lastRcvd;
	            dbg(TRANSPORT_CHANNEL, "Does not Loop!\n");
	         }
            if (bufflen  > rcvdLN)	//Not enough room in bufffer
	            dbg(TRANSPORT_CHANNEL, "Not enough room in buffer\n");
	         else 
            {
	            if (loop = 1 && (bufflen > x)) 
               {
                  dbg(TRANSPORT_CHANNEL, "here\n"); 
                  memcpy (socket.rcvdBuff - socket.lastRcvd, myMsg->payload, z*sizeof(uint8_t));
                  memcpy (socket.rcvdBuff, myMsg->payload - x, (bufflen - z)*sizeof(uint8_t));
                  socket.lastRcvd = bufflen - z;
	            }
	            else 
               {
                  memcpy (socket.rcvdBuff + socket.lastRcvd, myMsg->payload, bufflen*sizeof(uint8_t));
	               socket.lastRcvd += bufflen;
               }

               if(socket.lastRcvd > SOCKET_BUFFER_SIZE)
		            socket.lastRcvd -= SOCKET_BUFFER_SIZE;

               dbg(TRANSPORT_CHANNEL, "Sending DATA-ACK\n");

               tcpPacket = (tcpPack*) regPack.payload;
               tcpPacket->srcPort = socket.src.port;
               tcpPacket->destPort = socket.dest.port;
               tcpPacket->seq = seq + 1;
               tcpPacket->ack = seq + 1;
               tcpPacket->flag = 6;             //DATA-ACK flag

	            if (loop == 1) 
      	         tcpPacket->adWindow = x + socket.lastRead;
	            else
                  tcpPacket->adWindow = socket.lastRead - socket.lastRcvd;

               call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

               dbg(TRANSPORT_CHANNEL, "DATA-ACK being sent to %d from %d\n", socket.dest.addr, socket.src.addr);

               call TransportSender.send(regPack, AM_BROADCAST_ADDR);
	            call sMap.insert(fd, socket);
	         }
	      }
      }

      return SUCCESS;
   }

   command error_t Transport.connect(socket_t fd, socket_addr_t * addr)  //Make sure to reg everything inside socket ie ports & addrs
   {			
      //Does a hand shake for opening up a connection

      pack regPack;		//Normal pack to carry tcp pack
      tcpPack* tcpPacket;	//TCP pack with info

      socket = call sMap.get(fd);
      socket.dest.addr = addr->addr;
      socket.dest.port = addr->port;

      dbg(TRANSPORT_CHANNEL, "Connecting\n");

      tcpPacket = (tcpPack*) regPack.payload;

      tcpPacket->destPort = socket.dest.port;
      tcpPacket->srcPort = socket.src.port;
      srand(time(NULL));
      tcpPacket->seq = rand();
      tcpPacket->ack = 0;
      tcpPacket->flag = 0;
      tcpPacket->adWindow = SOCKET_BUFFER_SIZE;

      dbg(TRANSPORT_CHANNEL, "%d\n", fd);
      call sList.pushback(fd);
      
      //Creates a packet with payload tcp pack
      call Transport.makePack(&regPack, TOS_NODE_ID, socket.dest.addr, 32, 4, 0, tcpPacket, 0);

      dbg(TRANSPORT_CHANNEL, "SYN being sent to %d from %d\n", TOS_NODE_ID, socket.dest.addr);

      call TransportSender.send(regPack, AM_BROADCAST_ADDR);

      socket.state = SYN_SENT;		//Proves we were the ones that sent that SYN
      call sMap.insert(fd, socket);

      if(socket.state == ESTABLISHED)
	 return SUCCESS;
   }

   command error_t Transport.listen(socket_t fd) 
   {
      dbg(TRANSPORT_CHANNEL, "Listening\n");

      socket = call sMap.get(fd);

      if (socket.state == CLOSED) 
      {
	      socket.state = LISTEN;
	      call sMap.insert(fd, socket);
	      return SUCCESS;
      }
      else
      {
         return FAIL;
      }
	      
   }

   command void Transport.makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length)
   {
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

}