#include "utils.h"
#include "printf.h"

#define NNODE 8

module PANCoordinatorC {
	uses {
		interface Boot;
		interface AMSend;
        interface SplitControl;
        interface Receive;
        interface PacketAcknowledgements;
        interface Packet;
	}
}	implementation {
    bool connected_nodes[NNODE];
	message_t packet;
    my_msg_t * pckt;
    uint8_t node_ids;
	//void handle_connect(uint8_t node_id);
	task void sendConnack();
    //task void receiveMsg();

	event void Boot.booted()
    {
        call SplitControl.start();
    }

    event void SplitControl.startDone(error_t err)
    {
        if(err == SUCCESS)
        {
            printf("[PAN Coordinator] Started!\n");
        }
        else
        {
            call SplitControl.start();
        }
    }

    event void SplitControl.stopDone(error_t err) {
        printf("[PAN Coordinator] Something bad happened...\n");
    }

    event message_t* Receive.receive(message_t* buf, void* payload, uint8_t len){

    	my_msg_t* rx_msg = (my_msg_t*)payload;
    	
    	if(rx_msg->msg_type == CONNECT){
            //printf("Node %u sent me a packet, Previous message %u\n",rx_msg->nodeID, node_ids);
            node_ids = rx_msg->nodeID;
            if(!connected_nodes[node_ids - 1]){
                connected_nodes[node_ids - 1] = TRUE;
                post sendConnack();
            }
            else
                printf("[PAN Coordinator] Received message from %u but already connected\n",node_ids);
        }
        return buf;
    }

/*    void handle_connect(uint8_t node_id){


    	post sendConnack();

    }
*/
    task void sendConnack(){

        printf("[PAN Coordinator] Connect received from node :%u\n",node_ids);
        //node_ids = node_id;
        //printf("Node: %u\n", node_ids);
        pckt = call Packet.getPayload(&packet,sizeof(my_msg_t));
        pckt->msg_type = CONNACK;
        pckt->nodeID = AM_PAN_COORD_ADDR;
    	if( call AMSend.send(node_ids, &packet, sizeof(my_msg_t)) == SUCCESS)
    	{
    		printf("[PAN Coordinator] Sent Connack to node %u\n", node_ids);
    	}
    }

    
    event void AMSend.sendDone(message_t* buf,error_t err) {
        if(&packet == buf && err == SUCCESS )
            printf("[PAN Coordinator] Packet Sent\n");
        else if ( err != SUCCESS)
            printf("[PAN Coordinator] Packet NOT sent, failed\n");
    
        if ( call PacketAcknowledgements.wasAcked( buf ) )
          printf("[PAN Coordinator] Packet acked!\n");
    }
}