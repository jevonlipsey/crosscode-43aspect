#!/bin/bash
# blocks until the device lock is ours; exits 0 only when held
until ssh droiddeck 'mkdir /tmp/nova-43aspect.lock 2>/dev/null && echo "crosscode-43aspect $(date +%s)" > /tmp/nova-43aspect.lock/owner'; do sleep 30; done
echo LOCKED
