# UAF to page-table reclaim

Use this only when evidence shows that a stale kernel allocation can be reclaimed and the provided kernel image or configuration supports a page-table based path.

## Evidence chain

1. Reclaim the stale object with a structure that exposes a stable kernel function pointer. Derive the kernel slide only from known image symbols, and reject candidates that violate the expected large-page alignment.
2. Create bounded, well-separated user mappings so their page-table allocations can be distinguished. Use per-region markers rather than assuming allocator order.
3. Release data pages while keeping the relevant page-table structure alive, then scan the stale window for entries that match the target architecture's PTE shape.
4. Preserve the observed permission and attribute bits. Replace only the physical-frame field needed for the mapping, then force a controlled TLB refresh through a protection transition.
5. Before any write, verify that the remapped page contains expected, non-secret bytes from the intended target. A failed validation ends this path; it is not permission to scan arbitrary memory.
6. Prefer the shortest deterministic final effect supported by the supplied image and configuration. A helper-path overwrite can be simpler than a long ROP chain, but it must be proven available before use.

## Fast checks

- Confirm the reclaim object's size and the leaked pointer's symbol relationship from the supplied image.
- Check alignment and canonical-address properties before accepting a slide.
- Bound mapping count and scan range; print only stage, iteration, and return-code diagnostics.
- Validate target contents before modification and preserve the original PTE flags.

## Limits

- Reclaim order is probabilistic and kernel-version dependent; a local success is evidence for the primitive, not proof of identical remote layout.
- Do not substitute host kernel symbols, libc, or configuration for the supplied runtime.
- Do not continue with blind physical-memory scanning when structural checks fail.

This feedback contains no challenge-specific addresses, offsets, flags, payloads, or endpoint data.
