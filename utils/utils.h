
#ifndef UTILS_H
#define UTILS_H


typedef nx_struct my_msg_t {
	//nx_uint8_t header;
	nx_uint8_t msg_type;
	nx_uint8_t qos;
	nx_uint8_t nodeID;
	nx_uint16_t payload;
} my_msg_t;

#define CONNECT 1
#define CONNACK 2 
#define PUBLISH 3
#define PUBACK 4
#define SUBSCRIBE 5 
#define SUBACK 6

#define AM_PAN_COORD_ADDR 9 //AM_BROADCAST_ADDR

// 7 - 6 - 5 - 4 - 3 - 2 - 1 -0 
// msg type 7 -4
// 3 - 2 qos

// 

//payload--> topic 15 - 8, data 7 -0 
enum{
AM_MY_MSG = 6,
};

/*void simple_msg(puback_msg_t * msg,uint8_t node_id,uint8_t topic, uint8_t publish_id)
{
	*msg=PUBACK_CODE & NODE_ID_MASK;
	*msg|=(node_id & NODE_ID_MASK)<<PUBACK_NODE_ID_ALIGNMENT;
	*msg|=(topic & PUBLISH_TOPIC_MASK)<<PUBACK_TOPIC_ALIGNMENT;
	*msg|=publish_id<<PUBACK_ID_ALIGNMENT;
}*/


#endif