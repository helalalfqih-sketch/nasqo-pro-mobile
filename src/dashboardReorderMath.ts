export function reorderWithin(list: string[], source: string, destination: string): string[] {
  const from = list.indexOf(source), to = list.indexOf(destination);
  if (from < 0 || to < 0 || from === to) return list;
  const updated = [...list];
  const [item] = updated.splice(from, 1);
  updated.splice(to, 0, item);
  return updated;
}
