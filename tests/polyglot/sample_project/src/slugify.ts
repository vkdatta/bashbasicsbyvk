export function slugify(title: string, maxLength: number = 60): string {
  const lowered = title.toLowerCase().trim();
  const cleaned = lowered.replace(/[^a-z0-9]+/g, "-");
  const trimmed = cleaned.replace(/^-+|-+$/g, "");
  return trimmed.length > maxLength ? trimmed.slice(0, maxLength) : trimmed;
}
