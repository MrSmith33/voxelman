/*
 * Copyright (c) 2013 Derelict Developers
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 * * Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * * Neither the names 'Derelict', 'DerelictILUT', nor the names of its contributors
 *   may be used to endorse or promote products derived from this software
 *   without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
module derelict.enet.types;

version(BigEndian)
{
	ushort ENET_HOST_TO_NET_16(ushort x)
	{
		return x;
	}

	uint ENET_HOST_TO_NET_32(uint x)
	{
		return x;
	}
}
else version(LittleEndian)
{
	import core.bitop;
	ushort ENET_HOST_TO_NET_16(ushort x)
	{
		return ((x & 255) << 8) | (x >> 8);
	}

	uint ENET_HOST_TO_NET_32(uint x)
	{
		return bswap(x);
	}
}
else
	static assert(false, "Compiling on another planet!");

alias ENET_HOST_TO_NET_16 ENET_NET_TO_HOST_16;
alias ENET_HOST_TO_NET_32 ENET_NET_TO_HOST_32;


// win32.h

version(Windows)
{
	// some things from winsock2.h too

	version (X86_64)
		alias ulong SOCKET;
	else
		alias uint SOCKET;

	alias SOCKET ENetSocket;

	enum ENET_SOCKET_NULL = ~0;

	struct ENetBuffer
	{
		size_t dataLength;
		void * data;
	}

	enum FD_SETSIZE = 64;


	struct fd_set
	{
		uint fd_count;               /* how many are SET? */
		SOCKET[FD_SETSIZE] fd_array; /* an array of SOCKETs */
	}

	alias fd_set ENetSocketSet;

	void ENET_SOCKETSET_EMPTY(ref ENetSocketSet sockset)
	{
		sockset.fd_count = 0;
	}

	void ENET_SOCKETSET_ADD(ref ENetSocketSet sockset, ENetSocket socket)
	{
		uint i;
		for (i = 0; i < sockset.fd_count; ++i)
		{
			if (sockset.fd_array[i] == socket)
				break;
		}
		if (i == sockset.fd_count)
		{
			if (sockset.fd_count < FD_SETSIZE)
			{
				sockset.fd_array[i] = socket;
				sockset.fd_count++;
			}
		}
	}


	int ENET_SOCKETSET_CHECK(ref ENetSocketSet sockset, ENetSocket socket)
	{
		for (uint i = 0; i < sockset.fd_count; ++i)
		{
			if (sockset.fd_array[i] == socket)
				return 1;
		}
		return 0;
	}

	void ENET_SOCKETSET_REMOVE(ref ENetSocketSet sockset, ENetSocket socket)
	{
		for (uint i = 0; i < sockset.fd_count; ++i)
		{
			if (sockset.fd_array[i] == socket)
			{
				while (i < sockset.fd_count - 1)
				{
					sockset.fd_array[i] = sockset.fd_array[i + 1];
					i++;
				}
				sockset.fd_count--;
				break;
			}
		}
	}
}
else
{
	// unix.h

	import core.sys.posix.arpa.inet;
	import core.sys.posix.sys.select;

	alias int ENetSocket;

	enum ENET_SOCKET_NULL = -1;

	struct ENetBuffer
	{
		void* data;
		size_t dataLength;
	}

	alias fd_set ENetSocketSet;

	void ENET_SOCKETSET_EMPTY(ref ENetSocketSet sockset)
	{
		FD_ZERO(&sockset);
	}

	void ENET_SOCKETSET_ADD(ref ENetSocketSet sockset, ENetSocket socket)
	{
		FD_SET(socket, &sockset);
	}

	void ENET_SOCKETSET_REMOVE(ref ENetSocketSet sockset, ENetSocket socket)
	{
		FD_CLR(socket, &sockset);
	}

	bool ENET_SOCKETSET_CHECK(ref ENetSocketSet sockset, ENetSocket socket)
	{
		return FD_ISSET(socket, &sockset);
	}
}

// types.h
alias ubyte enet_uint8;       /**< unsigned 8-bit type  */
alias ushort enet_uint16;     /**< unsigned 16-bit type */
alias uint enet_uint32;       /**< unsigned 32-bit type */


// file  protocol.h

enum
{
	ENET_PROTOCOL_MINIMUM_MTU             = 576,
	ENET_PROTOCOL_MAXIMUM_MTU             = 4096,
	ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS = 32,
	ENET_PROTOCOL_MINIMUM_WINDOW_SIZE     = 4096,

	// Warning when using this constant, it depends on the linked library version:
	// - enet <= 1.3.9 defines ENET_PROTOCOL_MAXIMUM_WINDOW_SIZE as 32768
	// - enet >= 1.3.9 defines ENET_PROTOCOL_MAXIMUM_WINDOW_SIZE as 65536
	ENET_PROTOCOL_MAXIMUM_WINDOW_SIZE     = 65536,

	ENET_PROTOCOL_MINIMUM_CHANNEL_COUNT   = 1,
	ENET_PROTOCOL_MAXIMUM_CHANNEL_COUNT   = 255,
	ENET_PROTOCOL_MAXIMUM_PEER_ID         = 0xFFF,
	ENET_PROTOCOL_MAXIMUM_PACKET_SIZE     = 1024 * 1024 * 1024,
	ENET_PROTOCOL_MAXIMUM_FRAGMENT_COUNT  = 1024 * 1024
}

alias int ENetProtocolCommand;
enum : ENetProtocolCommand
{
	ENET_PROTOCOL_COMMAND_NONE               = 0,
	ENET_PROTOCOL_COMMAND_ACKNOWLEDGE        = 1,
	ENET_PROTOCOL_COMMAND_CONNECT            = 2,
	ENET_PROTOCOL_COMMAND_VERIFY_CONNECT     = 3,
	ENET_PROTOCOL_COMMAND_DISCONNECT         = 4,
	ENET_PROTOCOL_COMMAND_PING               = 5,
	ENET_PROTOCOL_COMMAND_SEND_RELIABLE      = 6,
	ENET_PROTOCOL_COMMAND_SEND_UNRELIABLE    = 7,
	ENET_PROTOCOL_COMMAND_SEND_FRAGMENT      = 8,
	ENET_PROTOCOL_COMMAND_SEND_UNSEQUENCED   = 9,
	ENET_PROTOCOL_COMMAND_BANDWIDTH_LIMIT    = 10,
	ENET_PROTOCOL_COMMAND_THROTTLE_CONFIGURE = 11,
	ENET_PROTOCOL_COMMAND_SEND_UNRELIABLE_FRAGMENT = 12,
	ENET_PROTOCOL_COMMAND_COUNT              = 13,

	ENET_PROTOCOL_COMMAND_MASK               = 0x0F
}

alias int ENetProtocolFlag;
enum : ENetProtocolFlag
{
	ENET_PROTOCOL_COMMAND_FLAG_ACKNOWLEDGE = (1 << 7),
	ENET_PROTOCOL_COMMAND_FLAG_UNSEQUENCED = (1 << 6),

	ENET_PROTOCOL_HEADER_FLAG_COMPRESSED = (1 << 14),
	ENET_PROTOCOL_HEADER_FLAG_SENT_TIME  = (1 << 15),
	ENET_PROTOCOL_HEADER_FLAG_MASK       = ENET_PROTOCOL_HEADER_FLAG_COMPRESSED | ENET_PROTOCOL_HEADER_FLAG_SENT_TIME,

	ENET_PROTOCOL_HEADER_SESSION_MASK    = (3 << 12),
	ENET_PROTOCOL_HEADER_SESSION_SHIFT   = 12
}

align(1) struct ENetProtocolHeader
{
	enet_uint16 peerID;
	enet_uint16 sentTime;
}

align(1) struct ENetProtocolCommandHeader
{
	enet_uint8 command;
	enet_uint8 channelID;
	enet_uint16 reliableSequenceNumber;
}

align(1) struct ENetProtocolAcknowledge
{
	ENetProtocolCommandHeader header;
	enet_uint16 receivedReliableSequenceNumber;
	enet_uint16 receivedSentTime;
}

align(1) struct ENetProtocolConnect
{
	ENetProtocolCommandHeader header;
	enet_uint16 outgoingPeerID;
	enet_uint8  incomingSessionID;
	enet_uint8  outgoingSessionID;
	enet_uint32 mtu;
	enet_uint32 windowSize;
	enet_uint32 channelCount;
	enet_uint32 incomingBandwidth;
	enet_uint32 outgoingBandwidth;
	enet_uint32 packetThrottleInterval;
	enet_uint32 packetThrottleAcceleration;
	enet_uint32 packetThrottleDeceleration;
	enet_uint32 connectID;
	enet_uint32 data;
}

align(1) struct ENetProtocolVerifyConnect
{
	ENetProtocolCommandHeader header;
	enet_uint16 outgoingPeerID;
	enet_uint8  incomingSessionID;
	enet_uint8  outgoingSessionID;
	enet_uint32 mtu;
	enet_uint32 windowSize;
	enet_uint32 channelCount;
	enet_uint32 incomingBandwidth;
	enet_uint32 outgoingBandwidth;
	enet_uint32 packetThrottleInterval;
	enet_uint32 packetThrottleAcceleration;
	enet_uint32 packetThrottleDeceleration;
	enet_uint32 connectID;
}

align(1) struct ENetProtocolBandwidthLimit
{
	ENetProtocolCommandHeader header;
	enet_uint32 incomingBandwidth;
	enet_uint32 outgoingBandwidth;
}

align(1) struct ENetProtocolThrottleConfigure
{
	ENetProtocolCommandHeader header;
	enet_uint32 packetThrottleInterval;
	enet_uint32 packetThrottleAcceleration;
	enet_uint32 packetThrottleDeceleration;
}

align(1) struct ENetProtocolDisconnect
{
	ENetProtocolCommandHeader header;
	enet_uint32 data;
}

align(1) struct ENetProtocolPing
{
	ENetProtocolCommandHeader header;
}

align(1) struct ENetProtocolSendReliable
{
	ENetProtocolCommandHeader header;
	enet_uint16 dataLength;
}

align(1) struct ENetProtocolSendUnreliable
{
	ENetProtocolCommandHeader header;
	enet_uint16 unreliableSequenceNumber;
	enet_uint16 dataLength;
}

align(1) struct ENetProtocolSendUnsequenced
{
	ENetProtocolCommandHeader header;
	enet_uint16 unsequencedGroup;
	enet_uint16 dataLength;
}

align(1) struct ENetProtocolSendFragment
{
	ENetProtocolCommandHeader header;
	enet_uint16 startSequenceNumber;
	enet_uint16 dataLength;
	enet_uint32 fragmentCount;
	enet_uint32 fragmentNumber;
	enet_uint32 totalLength;
	enet_uint32 fragmentOffset;
}

align(1) union ENetProtocol
{
	ENetProtocolCommandHeader header;
	ENetProtocolAcknowledge acknowledge;
	ENetProtocolConnect connect;
	ENetProtocolVerifyConnect verifyConnect;
	ENetProtocolDisconnect disconnect;
	ENetProtocolPing ping;
	ENetProtocolSendReliable sendReliable;
	ENetProtocolSendUnreliable sendUnreliable;
	ENetProtocolSendUnsequenced sendUnsequenced;
	ENetProtocolSendFragment sendFragment;
	ENetProtocolBandwidthLimit bandwidthLimit;
	ENetProtocolThrottleConfigure throttleConfigure;
}


// list.h
struct ENetListNode
{
	ENetListNode* next;
	ENetListNode* previous;
}

alias ENetListNode* ENetListIterator;

struct ENetList
{
	ENetListNode sentinel;
}

ENetListIterator enet_list_begin(ENetList* list)
{
	return list.sentinel.next;
}

ENetListIterator enet_list_end(ENetList* list)
{
	return &list.sentinel;
}

bool enet_list_empty(ENetList* list)
{
	return enet_list_begin(list) == enet_list_end(list);
}

ENetListIterator enet_list_next(ENetListIterator iterator)
{
	return iterator.next;
}

ENetListIterator enet_list_previous(ENetListIterator iterator)
{
	return iterator.previous;
}

void* enet_list_front(ENetList* list)
{
	return cast(void*)(list.sentinel.next);
}

void* enet_list_back(ENetList* list)
{
	return cast(void*)(list.sentinel.previous);
}


// callbacks.h

struct ENetCallbacks
{
	 extern(C) nothrow void* function(size_t size) malloc;
	 extern(C) nothrow void function(void* memory) free;
	 extern(C) nothrow void function() no_memory;
}

// enet.h

enum ENET_VERSION_MAJOR = 1;
enum ENET_VERSION_MINOR = 3;
enum ENET_VERSION_PATCH = 13;

int ENET_VERSION_CREATE(int major, int minor, int patch)
{
	 return (major << 16) | (minor << 8) | patch;
}

int ENET_VERSION_GET_MAJOR(int version_)
{
	return (version_ >> 16) & 0xFF;
}

int ENET_VERSION_GET_MINOR(int version_)
{
	return (version_ >> 8) & 0xFF;
}

int ENET_VERSION_GET_PATCH(int version_)
{
	return version_ & 0xFF;
}

enum ENET_VERSION = ENET_VERSION_CREATE(ENET_VERSION_MAJOR, ENET_VERSION_MINOR, ENET_VERSION_PATCH);

alias enet_uint32 ENetVersion;

alias int ENetSocketType;
enum : ENetSocketType
{
	ENET_SOCKET_TYPE_STREAM   = 1,
	ENET_SOCKET_TYPE_DATAGRAM = 2
}

alias int ENetSocketWait;
enum : ENetSocketWait
{
	ENET_SOCKET_WAIT_NONE      = 0,
	ENET_SOCKET_WAIT_SEND      = (1 << 0),
	ENET_SOCKET_WAIT_RECEIVE   = (1 << 1),
	ENET_SOCKET_WAIT_INTERRUPT = (1 << 2)
}

alias int ENetSocketOption;
enum : ENetSocketOption
{
	ENET_SOCKOPT_NONBLOCK  = 1,
	ENET_SOCKOPT_BROADCAST = 2,
	ENET_SOCKOPT_RCVBUF    = 3,
	ENET_SOCKOPT_SNDBUF    = 4,
	ENET_SOCKOPT_REUSEADDR = 5,
	ENET_SOCKOPT_RCVTIMEO  = 6,
	ENET_SOCKOPT_SNDTIMEO  = 7,
	ENET_SOCKOPT_ERROR     = 8
}

alias int ENetSocketShutdown;
enum : ENetSocketShutdown
{
	 ENET_SOCKET_SHUTDOWN_READ       = 0,
	 ENET_SOCKET_SHUTDOWN_WRITE      = 1,
	 ENET_SOCKET_SHUTDOWN_READ_WRITE = 2
}

enum ENET_HOST_ANY =       0;
enum ENET_HOST_BROADCAST = 0xFFFFFFFFU;
enum ENET_PORT_ANY =       0;

/**
 * Portable internet address structure.
 *
 * The host must be specified in network byte-order, and the port must be in host
 * byte-order. The constant ENET_HOST_ANY may be used to specify the default
 * server host. The constant ENET_HOST_BROADCAST may be used to specify the
 * broadcast address (255.255.255.255).  This makes sense for enet_host_connect,
 * but not for enet_host_create.  Once a server responds to a broadcast, the
 * address is updated from ENET_HOST_BROADCAST to the server's actual IP address.
 */
struct ENetAddress
{
	enet_uint32 host;
	enet_uint16 port;
}

/**
 * Packet flag bit constants.
 *
 * The host must be specified in network byte-order, and the port must be in
 * host byte-order. The constant ENET_HOST_ANY may be used to specify the
 * default server host.
 */
alias int ENetPacketFlag;
enum : ENetPacketFlag
{
	/** packet must be received by the target peer and resend attempts should be
	* made until the packet is delivered */
	ENET_PACKET_FLAG_RELIABLE    = (1 << 0),
	/** packet will not be sequenced with other packets
	* not supported for reliable packets
	*/
	ENET_PACKET_FLAG_UNSEQUENCED = (1 << 1),
	/** packet will not allocate data, and user must supply it instead */
	ENET_PACKET_FLAG_NO_ALLOCATE = (1 << 2),
	/** packet will be fragmented using unreliable (instead of reliable) sends
	* if it exceeds the MTU */
	ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT = (1 << 3),

	/** whether the packet has been sent from all queues it has been entered into */
	ENET_PACKET_FLAG_SENT = (1<<8)
}

alias extern(C) nothrow void function(ENetPacket *) ENetPacketFreeCallback;

/**
 * ENet packet structure.
 *
 * An ENet data packet that may be sent to or received from a peer. The shown
 * fields should only be read and never modified. The data field contains the
 * allocated data for the packet. The dataLength fields specifies the length
 * of the allocated data.  The flags field is either 0 (specifying no flags),
 * or a bitwise-or of any combination of the following flags:
 *
 *    ENET_PACKET_FLAG_RELIABLE - packet must be received by the target peer
 *    and resend attempts should be made until the packet is delivered
 *
 *    ENET_PACKET_FLAG_UNSEQUENCED - packet will not be sequenced with other packets
 *    (not supported for reliable packets)
 *
 *    ENET_PACKET_FLAG_NO_ALLOCATE - packet will not allocate data, and user must supply it instead
 */
struct ENetPacket
{
	size_t                   referenceCount;  /**< internal use only */
	enet_uint32              flags;           /**< bitwise-or of ENetPacketFlag constants */
	enet_uint8 *             data;            /**< allocated data for packet */
	size_t                   dataLength;      /**< length of data */
	ENetPacketFreeCallback   freeCallback;    /**< function to be called when the packet is no longer in use */
	void *                   userData;        /**< application private data, may be freely modified */
}

struct ENetAcknowledgement
{
	ENetListNode acknowledgementList;
	enet_uint32  sentTime;
	ENetProtocol command;
}

struct ENetOutgoingCommand
{
	ENetListNode outgoingCommandList;
	enet_uint16  reliableSequenceNumber;
	enet_uint16  unreliableSequenceNumber;
	enet_uint32  sentTime;
	enet_uint32  roundTripTimeout;
	enet_uint32  roundTripTimeoutLimit;
	enet_uint32  fragmentOffset;
	enet_uint16  fragmentLength;
	enet_uint16  sendAttempts;
	ENetProtocol command;
	ENetPacket * packet;
}

struct ENetIncomingCommand
{
	ENetListNode     incomingCommandList;
	enet_uint16      reliableSequenceNumber;
	enet_uint16      unreliableSequenceNumber;
	ENetProtocol     command;
	enet_uint32      fragmentCount;
	enet_uint32      fragmentsRemaining;
	enet_uint32 *    fragments;
	ENetPacket *     packet;
}

alias int ENetPeerState;
enum : ENetPeerState
{
	ENET_PEER_STATE_DISCONNECTED                = 0,
	ENET_PEER_STATE_CONNECTING                  = 1,
	ENET_PEER_STATE_ACKNOWLEDGING_CONNECT       = 2,
	ENET_PEER_STATE_CONNECTION_PENDING          = 3,
	ENET_PEER_STATE_CONNECTION_SUCCEEDED        = 4,
	ENET_PEER_STATE_CONNECTED                   = 5,
	ENET_PEER_STATE_DISCONNECT_LATER            = 6,
	ENET_PEER_STATE_DISCONNECTING               = 7,
	ENET_PEER_STATE_ACKNOWLEDGING_DISCONNECT    = 8,
	ENET_PEER_STATE_ZOMBIE                      = 9
}

enum ENET_BUFFER_MAXIMUM  = 1 + 2 * ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS;

enum : int
{
	ENET_HOST_RECEIVE_BUFFER_SIZE          = 256 * 1024,
	ENET_HOST_SEND_BUFFER_SIZE             = 256 * 1024,
	ENET_HOST_BANDWIDTH_THROTTLE_INTERVAL  = 1000,
	ENET_HOST_DEFAULT_MTU                  = 1400,

	ENET_PEER_DEFAULT_ROUND_TRIP_TIME      = 500,
	ENET_PEER_DEFAULT_PACKET_THROTTLE      = 32,
	ENET_PEER_PACKET_THROTTLE_SCALE        = 32,
	ENET_PEER_PACKET_THROTTLE_COUNTER      = 7,
	ENET_PEER_PACKET_THROTTLE_ACCELERATION = 2,
	ENET_PEER_PACKET_THROTTLE_DECELERATION = 2,
	ENET_PEER_PACKET_THROTTLE_INTERVAL     = 5000,
	ENET_PEER_PACKET_LOSS_SCALE            = (1 << 16),
	ENET_PEER_PACKET_LOSS_INTERVAL         = 10000,
	ENET_PEER_WINDOW_SIZE_SCALE            = 64 * 1024,
	ENET_PEER_TIMEOUT_LIMIT                = 32,
	ENET_PEER_TIMEOUT_MINIMUM              = 5000,
	ENET_PEER_TIMEOUT_MAXIMUM              = 30000,
	ENET_PEER_PING_INTERVAL                = 500,
	ENET_PEER_UNSEQUENCED_WINDOWS          = 64,
	ENET_PEER_UNSEQUENCED_WINDOW_SIZE      = 1024,
	ENET_PEER_FREE_UNSEQUENCED_WINDOWS     = 32,
	ENET_PEER_RELIABLE_WINDOWS             = 16,
	ENET_PEER_RELIABLE_WINDOW_SIZE         = 0x1000,
	ENET_PEER_FREE_RELIABLE_WINDOWS        = 8
}

struct ENetChannel
{
	enet_uint16  outgoingReliableSequenceNumber;
	enet_uint16  outgoingUnreliableSequenceNumber;
	enet_uint16  usedReliableWindows;
	enet_uint16[ENET_PEER_RELIABLE_WINDOWS] reliableWindows;
	enet_uint16  incomingReliableSequenceNumber;
	enet_uint16  incomingUnreliableSequenceNumber;
	ENetList     incomingReliableCommands;
	ENetList     incomingUnreliableCommands;
}

/**
 * An ENet peer which data packets may be sent or received from.
 *
 * No fields should be modified unless otherwise specified.
 */
struct ENetPeer
{
	ENetListNode  dispatchList;
	ENetHost * host;
	enet_uint16   outgoingPeerID;
	enet_uint16   incomingPeerID;
	enet_uint32   connectID;
	enet_uint8    outgoingSessionID;
	enet_uint8    incomingSessionID;
	ENetAddress   address;            /**< Internet address of the peer */
	void *        data;               /**< Application private data, may be freely modified */
	ENetPeerState state;
	ENetChannel * channels;
	size_t        channelCount;       /**< Number of channels allocated for communication with peer */
	enet_uint32   incomingBandwidth;  /**< Downstream bandwidth of the client in bytes/second */
	enet_uint32   outgoingBandwidth;  /**< Upstream bandwidth of the client in bytes/second */
	enet_uint32   incomingBandwidthThrottleEpoch;
	enet_uint32   outgoingBandwidthThrottleEpoch;
	enet_uint32   incomingDataTotal;
	enet_uint32   outgoingDataTotal;
	enet_uint32   lastSendTime;
	enet_uint32   lastReceiveTime;
	enet_uint32   nextTimeout;
	enet_uint32   earliestTimeout;
	enet_uint32   packetLossEpoch;
	enet_uint32   packetsSent;
	enet_uint32   packetsLost;
	enet_uint32   packetLoss;          /**< mean packet loss of reliable packets as a ratio with respect to the constant ENET_PEER_PACKET_LOSS_SCALE */
	enet_uint32   packetLossVariance;
	enet_uint32   packetThrottle;
	enet_uint32   packetThrottleLimit;
	enet_uint32   packetThrottleCounter;
	enet_uint32   packetThrottleEpoch;
	enet_uint32   packetThrottleAcceleration;
	enet_uint32   packetThrottleDeceleration;
	enet_uint32   packetThrottleInterval;
	enet_uint32   pingInterval;
	enet_uint32   timeoutLimit;
	enet_uint32   timeoutMinimum;
	enet_uint32   timeoutMaximum;
	enet_uint32   lastRoundTripTime;
	enet_uint32   lowestRoundTripTime;
	enet_uint32   lastRoundTripTimeVariance;
	enet_uint32   highestRoundTripTimeVariance;
	enet_uint32   roundTripTime;            /**< mean round trip time (RTT), in milliseconds, between sending a reliable packet and receiving its acknowledgement */
	enet_uint32   roundTripTimeVariance;
	enet_uint32   mtu;
	enet_uint32   windowSize;
	enet_uint32   reliableDataInTransit;
	enet_uint16   outgoingReliableSequenceNumber;
	ENetList      acknowledgements;
	ENetList      sentReliableCommands;
	ENetList      sentUnreliableCommands;
	ENetList      outgoingReliableCommands;
	ENetList      outgoingUnreliableCommands;
	ENetList      dispatchedCommands;
	int           needsDispatch;
	enet_uint16   incomingUnsequencedGroup;
	enet_uint16   outgoingUnsequencedGroup;
	enet_uint32[ENET_PEER_UNSEQUENCED_WINDOW_SIZE / 32] unsequencedWindow;
	enet_uint32   eventData;
	size_t        totalWaitingData;
}

/** An ENet packet compressor for compressing UDP packets before socket sends or receives.
 */
struct ENetCompressor
{
	/** Context data for the compressor. Must be non-NULL. */
	void * context;
	/** Compresses from inBuffers[0:inBufferCount-1], containing inLimit bytes, to outData, outputting at most outLimit bytes. Should return 0 on failure. */
	extern(C) nothrow size_t function(void * context, const ENetBuffer * inBuffers, size_t inBufferCount, size_t inLimit, enet_uint8 * outData, size_t outLimit) compress;
	/** Decompresses from inData, containing inLimit bytes, to outData, outputting at most outLimit bytes. Should return 0 on failure. */
	extern(C) nothrow size_t function(void * context, const enet_uint8 * inData, size_t inLimit, enet_uint8 * outData, size_t outLimit) decompress;
	/** Destroys the context when compression is disabled or the host is destroyed. May be NULL. */
	extern(C) nothrow void function(void * context) destroy;
}

/** Callback that computes the checksum of the data held in buffers[0:bufferCount-1] */
alias extern(C) nothrow enet_uint32 function(const ENetBuffer * buffers, size_t bufferCount) ENetChecksumCallback;

/** Callback for intercepting received raw UDP packets. Should return 1 to intercept, 0 to ignore, or -1 to propagate an error. */
alias extern(C) nothrow int function(ENetHost * host, ENetEvent * event) ENetInterceptCallback;

/** An ENet host for communicating with peers.
  *
  * No fields should be modified unless otherwise stated.

	@sa enet_host_create()
	@sa enet_host_destroy()
	@sa enet_host_connect()
	@sa enet_host_service()
	@sa enet_host_flush()
	@sa enet_host_broadcast()
	@sa enet_host_compress()
	@sa enet_host_compress_with_range_coder()
	@sa enet_host_channel_limit()
	@sa enet_host_bandwidth_limit()
	@sa enet_host_bandwidth_throttle()
*/
struct ENetHost
{
	ENetSocket           socket;
	ENetAddress          address;                     /**< Internet address of the host */
	enet_uint32          incomingBandwidth;           /**< downstream bandwidth of the host */
	enet_uint32          outgoingBandwidth;           /**< upstream bandwidth of the host */
	enet_uint32          bandwidthThrottleEpoch;
	enet_uint32          mtu;
	enet_uint32          randomSeed;
	int                  recalculateBandwidthLimits;
	ENetPeer *           peers;                       /**< array of peers allocated for this host */
	size_t               peerCount;                   /**< number of peers allocated for this host */
	size_t               channelLimit;                /**< maximum number of channels allowed for connected peers */
	enet_uint32          serviceTime;
	ENetList             dispatchQueue;
	int                  continueSending;
	size_t               packetSize;
	enet_uint16          headerFlags;
	ENetProtocol[ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS] commands;
	size_t               commandCount;
	ENetBuffer[ENET_BUFFER_MAXIMUM] buffers ;
	size_t               bufferCount;
	ENetChecksumCallback checksum;                    /**< callback the user can set to enable packet checksums for this host */
	ENetCompressor       compressor;
	enet_uint8[ENET_PROTOCOL_MAXIMUM_MTU][2] packetData;
	ENetAddress          receivedAddress;
	enet_uint8 *         receivedData;
	size_t               receivedDataLength;
	enet_uint32          totalSentData;               /**< total data sent, user should reset to 0 as needed to prevent overflow */
	enet_uint32          totalSentPackets;            /**< total UDP packets sent, user should reset to 0 as needed to prevent overflow */
	enet_uint32          totalReceivedData;           /**< total data received, user should reset to 0 as needed to prevent overflow */
	enet_uint32          totalReceivedPackets;        /**< total UDP packets received, user should reset to 0 as needed to prevent overflow */
	ENetInterceptCallback intercept;                  /**< callback the user can set to intercept received raw UDP packets */
	size_t               connectedPeers;
	size_t               bandwidthLimitedPeers;
	size_t               duplicatePeers;              /**< optional number of allowed peers from duplicate IPs, defaults to ENET_PROTOCOL_MAXIMUM_PEER_ID */
	size_t               maximumPacketSize;           /**< the maximum allowable packet size that may be sent or received on a peer */
	size_t               maximumWaitingData;          /**< the maximum aggregate amount of buffer space a peer may use waiting for packets to be delivered */
}

/**
 * An ENet event type, as specified in @ref ENetEvent.
 */
alias int ENetEventType;
enum : ENetEventType
{
	/** no event occurred within the specified time limit */
	ENET_EVENT_TYPE_NONE       = 0,

	/** a connection request initiated by enet_host_connect has completed.
	* The peer field contains the peer which successfully connected.
	*/
	ENET_EVENT_TYPE_CONNECT    = 1,

	/** a peer has disconnected.  This event is generated on a successful
	* completion of a disconnect initiated by enet_pper_disconnect, if
	* a peer has timed out, or if a connection request intialized by
	* enet_host_connect has timed out.  The peer field contains the peer
	* which disconnected. The data field contains user supplied data
	* describing the disconnection, or 0, if none is available.
	*/
	ENET_EVENT_TYPE_DISCONNECT = 2,

	/** a packet has been received from a peer.  The peer field specifies the
	* peer which sent the packet.  The channelID field specifies the channel
	* number upon which the packet was received.  The packet field contains
	* the packet that was received; this packet must be destroyed with
	* enet_packet_destroy after use.
	*/
	ENET_EVENT_TYPE_RECEIVE    = 3
}

/**
 * An ENet event as returned by enet_host_service().
 */
struct ENetEvent
{
	ENetEventType        type;      /**< type of the event */
	ENetPeer *           peer;      /**< peer that generated a connect, disconnect or receive event */
	enet_uint8           channelID; /**< channel on the peer that generated the event, if appropriate */
	enet_uint32          data;      /**< data associated with the event, if appropriate */
	ENetPacket *         packet;    /**< packet associated with the event, if appropriate */
}

