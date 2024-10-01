from contextlib import contextmanager, asynccontextmanager
import asyncio
import json
import socket

mpv_path = 'build/mpv'

class IpcError(Exception):
    pass

class Mpv:
    default_args = [
        '--idle',
        '--vo=null',
        '--ao=null',
        '--no-ytdl',
        '--load-stats-overlay=no',
        '--load-osd-console=no',
        '--load-auto-profiles=no',
    ]

    @classmethod
    async def create(cls, *args):
        self = cls()
        self.request_id = 0
        self.args = args
        self.pending_requests = {}
        self.event_handlers = []
        self.observe_property_id = 0

        our_end, mpv_end = socket.socketpair()

        self.process = await asyncio.create_subprocess_exec(
            mpv_path,
            '--no-config',
            '--msg-level=ipc=trace',
            '--input-ipc-client=fd://0',
            *cls.default_args,
            *args,
            stdin=mpv_end,
        )

        mpv_end.close()

        self.sock = our_end
        self.reader, self.writer = await asyncio.open_connection(sock=self.sock)

        loop = asyncio.get_running_loop()
        loop.create_task(self._read_lines())

        return self

    @contextmanager
    def event_handler(self, handler):
        try:
            self.event_handlers.append(handler)
            yield
        finally:
            self.event_handlers.remove(handler)

    def set_property(self, name, value):
        return self.command('set_property', name, value)

    async def command(self, *args):
        self.request_id += 1
        request_id = self.request_id

        data = {
            'command': args,
            'request_id': request_id,
            'async': True,
        }
        print('>', data)
        line = bytes(json.dumps(data).encode('utf-8')) + b'\n'

        loop = asyncio.get_running_loop()
        done = loop.create_future()

        try:
            self.pending_requests[request_id] = done

            self.writer.write(line)
            await self.writer.drain()

            return await done
        finally:
            del self.pending_requests[request_id]

    def close(self):
        # self.sock.close()
        self.writer.close()

    async def property_changed(self, name):
        self.observe_property_id += 1
        id = self.observe_property_id

        loop = asyncio.get_running_loop()
        installed = loop.create_future()
        changed = loop.create_future()

        first = True

        def handler(data):
            nonlocal first
            nonlocal self

            if data['event'] == 'property-change' and data['id'] == id:
                if first:
                    first = False
                    installed.set_result(None)
                    return

                changed.set_result(data)

                self.event_handlers.remove(handler)
                loop.create_task(self.command('unobserve_property', id))

        self.event_handlers.append(handler)

        await self.command('observe_property', id, name)
        await installed

        print('* Waiting for %r property to change' % name)

        return changed

    def event_received(self, name):
        print('* Waiting for %r event' % name)

        loop = asyncio.get_running_loop()
        received = loop.create_future()

        def handler(data):
            if data['event'] == name:
                self.event_handlers.remove(handler)
                received.set_result(data)

        self.event_handlers.append(handler)

        return received

    async def closed(self):
        await self.writer.wait_closed()
        await self.process.wait()

    async def _read_lines(self):
        while True:
            line = await self.reader.readline()

            if not line:
                break

            data =  json.loads(line)
            print('<', data)

            if event := data.get('event'):
                for handler in list(self.event_handlers):
                    handler(data)
            else:
                done = self.pending_requests[data['request_id']]
                if data['error'] == 'success':
                    done.set_result(data.get('data', None))
                else:
                    done.set_exception(IpcError(data['error']))

        self.writer.close()
        # await self.writer.wait_closed()

        for done in self.pending_requests.values():
            done.cancel()

    def __repr__(self):
        return (f"Mpv(args={self.args!r})")

@asynccontextmanager
async def mpv(*args, **kwargs):
    m = await Mpv.create(*args, **kwargs)
    try:
        yield m
    finally:
        m.close()
        await m.closed()

# b = await mpv.property_changed('playlist')
# print(await mpv.command('loadfile', '../a.mp3'))
# await mpv.command('set_property', 'playlist', [1, 0])
# print('GOT', await b)
# await mpv.command('quit')
# assert r == [{'filename': 'kecskeszar', 'id': 2}, {'filename': 'lofasz', 'id': 2}]

async def main():
    anull = 'av://lavfi:anullsrc'

    async with mpv() as m:
        event = m.event_received('start-file')
        await m.set_property('playlist', [anull, anull])
        await m.set_property('playlist', [dict(id = 2, current = True)])
        assert await event == {'event': 'start-file', 'playlist_entry_id': 2}

asyncio.run(main())
