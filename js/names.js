// Nomes digitados por qualquer pessoa: limpa e impede que alguém use o nome de outro (igual ao servidor online).

// Tira caracteres invisíveis ou de controle (inclusive os que invertem a direção do texto), junta espaços e corta.
export function cleanName(v, n = 14) {
  let s = typeof v === 'string' ? v : '';
  s = s.replace(/[\p{Cc}\p{Cf}\p{Co}\p{Cs}�]/gu, '').replace(/^\p{Mn}+/u, '').replace(/\s+/gu, ' ').trim();
  const chars = [...s];
  return chars.length > n ? chars.slice(0, n).join('').trim() : s;
}

const FOLD = {
  á: 'a', à: 'a', â: 'a', ã: 'a', ä: 'a', å: 'a', а: 'a', α: 'a', é: 'e', è: 'e', ê: 'e', ë: 'e', е: 'e', ε: 'e',
  í: 'i', ì: 'i', î: 'i', ï: 'i', і: 'i', ι: 'i', ó: 'o', ò: 'o', ô: 'o', õ: 'o', ö: 'o', о: 'o', ο: 'o', 0: 'o',
  ú: 'u', ù: 'u', û: 'u', ü: 'u', υ: 'u', ç: 'c', с: 'c', ñ: 'n', ý: 'y', у: 'y', р: 'p', ρ: 'p', х: 'x', χ: 'x',
  ј: 'j', ѕ: 's', ԁ: 'd', κ: 'k', ν: 'v', τ: 't', һ: 'h', ԛ: 'q', ԝ: 'w',
};
// Dois nomes com a mesma chave parecem o mesmo na tela (acentos, letras de outros alfabetos que imitam as nossas).
export const nameKey = (s) => [...String(s).toLowerCase()].map((c) => FOLD[c] || c).filter((c) => /[\p{L}\p{N}]/u.test(c)).join('');
const botLike = (k) => /^bot\d*$/.test(k);

// Nome que não se confunde com o de nenhum outro lugar (self é ignorado): "Luiz" já usado vira "Luiz 2".
export function uniqueName(name, seats, self = null, isBot = false) {
  if (!name || !nameKey(name) || (!isBot && botLike(nameKey(name)))) name = 'Convidado';
  const taken = (n) => seats.some((s) => s !== self && nameKey(s.name) === nameKey(n));
  if (!taken(name)) return name;
  for (let i = 2; ; i++) {
    const suf = ' ' + i, base = [...name].slice(0, 14 - suf.length).join('').trim();
    if (!taken(base + suf)) return base + suf;
  }
}
