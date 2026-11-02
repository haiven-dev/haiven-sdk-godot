using System;
using Godot;
using Haiven.Sdk;

namespace Haiven.Sdk.Godot
{
    /// <summary>
    /// The Godot transport half of the .NET flavour. WebSocketPeer only makes
    /// progress when polled, so a HaivenDotNetSession drives this from _Process.
    /// </summary>
    public sealed class GodotWebSocket : IHaivenSocket
    {
        private readonly WebSocketPeer peer;
        private bool opened;
        private bool closed;

        public GodotWebSocket(WebSocketPeer? peer = null)
        {
            this.peer = peer ?? new WebSocketPeer();
        }

        public event Action? Opened;

        public event Action<string>? Received;

        public event Action<int, string>? Closed;

        public Error ConnectToUrl(string url)
        {
            opened = false;
            closed = false;
            return peer.ConnectToUrl(url);
        }

        /// <summary>Polls once and returns false after the close event is emitted.</summary>
        public bool Poll()
        {
            if (closed) return false;

            peer.Poll();
            var state = peer.GetReadyState();

            if (state == WebSocketPeer.State.Open && !opened)
            {
                opened = true;
                Opened?.Invoke();
            }

            while (peer.GetAvailablePacketCount() > 0)
            {
                Received?.Invoke(peer.GetPacket().GetStringFromUtf8());
            }

            if (state == WebSocketPeer.State.Closed)
            {
                closed = true;
                Closed?.Invoke((int)peer.GetCloseCode(), peer.GetCloseReason());
                return false;
            }

            return true;
        }

        public void Send(string payload)
        {
            var error = peer.SendText(payload);
            if (error != Error.Ok)
            {
                throw new InvalidOperationException($"haiven: WebSocketPeer.SendText failed: {error}");
            }
        }

        public void Close()
        {
            if (!closed) peer.Close();
        }
    }
}
