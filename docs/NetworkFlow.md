# ClodRiver Network Flow

## Swim Lane Diagram: Startup & Listener Creation

```
Server.coffee          $sys              listener          listen BIF        Node net.Server
     |                  |                    |                  |                   |
     |--loadCore()----->|                    |                  |                   |
     |                  |                    |                  |                   |
     |--call('startup')-|                    |                  |                   |
     |                  |                    |                  |                   |
     |                  |--spawn_listener()->|                  |                   |
     |                  |                    |                  |                   |
     |                  |                    |--listen(opts)--->|                   |
     |                  |                    |                  |                   |
     |                  |                    |                  |--createServer()-->|
     |                  |                    |                  |                   |
     |                  |                    |                  |--listen(port)---->|
     |                  |                    |                  |                   |
     |                  |                    |<---return--------|                   |
     |                  |                    |  (listener with _netServer)          |
```

## Swim Lane Diagram: Client Connection

```
Client    Node Socket    listen BIF    listener    accept BIF    connection    $admin
  |            |              |            |             |             |           |
  |--connect-->|              |            |             |             |           |
  |            |              |            |             |             |           |
  |            |--(callback)->|            |             |             |           |
  |            |              |            |             |             |           |
  |            |        store socket      |             |             |           |
  |            |        as _pendingSocket |             |             |           |
  |            |              |            |             |             |           |
  |            |              |--connected(socketInfo)->|             |           |
  |            |              |            |             |             |           |
  |            |              |            |--spawn()----------------->|           |
  |            |              |            |             |             |           |
  |            |              |            |<---new connection---------|           |
  |            |              |            |             |             |           |
  |            |              |            |--accept(connection)------>|           |
  |            |              |            |             |             |           |
  |            |              |            |     get _pendingSocket    |           |
  |            |              |            |     assign to             |           |
  |            |              |            |     connection._socket    |           |
  |            |              |            |             |             |           |
  |            |              |            |     setup handlers:       |           |
  |            |              |            |     socket.on('data',     |           |
  |            |              |            |       ->connection.data)  |           |
  |            |              |            |     socket.on('close')    |           |
  |            |              |            |             |             |           |
  |            |              |            |             |--connected()->           |
  |            |              |            |             |             |           |
  |            |              |            |             |             |--set_connection->
  |            |              |            |             |             |           |
  |            |              |            |             |<------------|           |
```

## Swim Lane Diagram: Data Flow (Client to Server)

```
Client    Node Socket    accept's handler    connection    $admin
  |            |                |                 |            |
  |--send("1+1\n")              |                 |            |
  |            |                |                 |            |
  |            |--'data' event->|                 |            |
  |            |                |                 |            |
  |            |                |--call('data',buf)            |
  |            |                |                 |            |
  |            |                |          parse lines        |
  |            |                |          buffer management  |
  |            |                |                 |            |
  |            |                |                 |--receive_line(line)
  |            |                |                 |            |
  |            |                |                 |     eval code
  |            |                |                 |            |
  |            |                |                 |<--result---|
  |            |                |                 |            |
  |            |                |                 |--notify("=> 2")
  |            |                |                 |            |
  |            |                |                 |     cget('connection')
  |            |                |                 |            |
  |            |                |                 |<--connection--
  |            |                |                 |            |
```

## Swim Lane Diagram: Data Flow (Server to Client)

```
$admin    connection    emit BIF    connection._socket    Client
  |            |            |               |               |
  |--send(connection,      |               |               |
  |    'emit', "=> 2")     |               |               |
  |            |            |               |               |
  |            |--emit("=> 2")             |               |
  |            |            |               |               |
  |            |            |--ctx.cthis()->|               |
  |            |            |  (connection) |               |
  |            |            |               |               |
  |            |            |--write("=> 2")-->            |
  |            |            |               |               |
  |            |            |               |---send------->|
  |            |            |               |               |
```

## Key Points

1. **Node Socket Events are the Source**
   - socket 'data' event triggers connection.data()
   - socket 'close' event triggers connection.disconnected()
   - socket 'error' is logged directly

2. **accept BIF is the Bridge**
   - Sets up event handlers that bridge Node events to ClodMUD methods
   - Associates the socket with the connection object
   - Does NOT originate events - just handles them

3. **Method Names Mirror Node Events**
   - 'data' method matches socket 'data' event
   - 'disconnected' method matches socket 'close' event
   - 'connected' method is called after accept completes setup

4. **Current Missing Pieces**
   - listener.connected() method (should spawn connection and call accept)
   - connection.connected() method (should tell $admin about connection)
   - $admin.set_connection() method (should store connection in state)

5. **Data Flow is Bidirectional**
   - Inbound: socket 'data' event → connection.data → $admin.receive_line
   - Outbound: $admin.notify → connection.emit → emit BIF → socket.write
