{
  writeShellApplication,
  wireguard-tools,
  iptables,

  netns ? "hydrus",
  wgService ? "192.168.2.2",
}:
writeShellApplication {
  name = "hydrus-testutil-stop-wireguard-tunnel";
  runtimeInputs = [
    wireguard-tools
    iptables
  ];
  text = ''
    iptables -t nat -D POSTROUTING -s ${wgService}/32 -o eth0 -j MASQUERADE
    iptables -D FORWARD -i wg0 -j ACCEPT
    iptables -D FORWARD -o wg0 -j ACCEPT

    ip link set wg0 down
    ip link delete wg0

    ip -n ${netns} route del default dev wg1
    ip -n ${netns} set wg1 down
    ip -n ${netns} link delete wg1
  '';
}
