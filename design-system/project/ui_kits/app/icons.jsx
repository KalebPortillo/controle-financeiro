// ============================================================
// Controle Financeiro — Lucide icon set
// Inline SVG so the kit works offline. Stroke / width / line caps
// match Lucide defaults exactly.
// ============================================================

const Icon = ({ d, size = 16, className = '', style }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="1.75"
    strokeLinecap="round"
    strokeLinejoin="round"
    className={className}
    style={style}
    aria-hidden="true"
  >
    {d}
  </svg>
);

const Wallet = (p) => <Icon {...p} d={<>
  <path d="M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a8 8 0 0 0-16 0V21a1 1 0 0 0 1 1h13a1 1 0 0 0 1-1v-3" />
</>} />;

const Inbox = (p) => <Icon {...p} d={<>
  <polyline points="22 12 16 12 14 15 10 15 8 12 2 12" />
  <path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z" />
</>} />;

const PieChartIcon = (p) => <Icon {...p} d={<>
  <path d="M21.21 15.89A10 10 0 1 1 8 2.83" />
  <path d="M22 12A10 10 0 0 0 12 2v10z" />
</>} />;

const BarChart3 = (p) => <Icon {...p} d={<>
  <path d="M3 3v18h18" />
  <path d="M18 17V9" />
  <path d="M13 17V5" />
  <path d="M8 17v-3" />
</>} />;

const MoreHorizontal = (p) => <Icon {...p} d={<>
  <circle cx="12" cy="12" r="1" />
  <circle cx="19" cy="12" r="1" />
  <circle cx="5" cy="12" r="1" />
</>} />;

const Check = (p) => <Icon {...p} d={<polyline points="20 6 9 17 4 12" />} />;

const X = (p) => <Icon {...p} d={<>
  <line x1="18" x2="6" y1="6" y2="18" />
  <line x1="6" x2="18" y1="6" y2="18" />
</>} />;

const Split = (p) => <Icon {...p} d={<>
  <path d="M16 3h5v5" /><path d="M8 3H3v5" /><path d="m21 3-7 7" />
  <path d="m3 3 7 7" /><path d="M3 16v5h5" /><path d="m3 21 7-7" />
  <path d="M16 21h5v-5" /><path d="m14 14 7 7" />
</>} />;

const Trash2 = (p) => <Icon {...p} d={<>
  <path d="M3 6h18" />
  <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" />
  <path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
</>} />;

const Link2 = (p) => <Icon {...p} d={<>
  <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
  <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
</>} />;

const Search = (p) => <Icon {...p} d={<>
  <circle cx="11" cy="11" r="8" /><path d="m21 21-4.3-4.3" />
</>} />;

const Plus = (p) => <Icon {...p} d={<>
  <path d="M5 12h14" /><path d="M12 5v14" />
</>} />;

const Calendar = (p) => <Icon {...p} d={<>
  <rect width="18" height="18" x="3" y="4" rx="2" />
  <path d="M16 2v4" /><path d="M8 2v4" /><path d="M3 10h18" />
</>} />;

const TagIcon = (p) => <Icon {...p} d={<>
  <path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z" />
  <circle cx="7.5" cy="7.5" r=".5" fill="currentColor" />
</>} />;

const FolderIcon = (p) => <Icon {...p} d={<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.93a2 2 0 0 1-1.66-.9l-.82-1.2A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z" />} />;

const ChevronDown = (p) => <Icon {...p} d={<path d="m6 9 6 6 6-6" />} />;
const ChevronRight = (p) => <Icon {...p} d={<path d="m9 18 6-6-6-6" />} />;
const ArrowLeft = (p) => <Icon {...p} d={<><path d="m12 19-7-7 7-7" /><path d="M19 12H5" /></>} />;

const Moon = (p) => <Icon {...p} d={<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z" />} />;
const Sun = (p) => <Icon {...p} d={<>
  <circle cx="12" cy="12" r="4" />
  <path d="M12 2v2" /><path d="M12 20v2" /><path d="m4.93 4.93 1.41 1.41" />
  <path d="m17.66 17.66 1.41 1.41" /><path d="M2 12h2" /><path d="M20 12h2" />
  <path d="m6.34 17.66-1.41 1.41" /><path d="m19.07 4.93-1.41 1.41" />
</>} />;

const Bell = (p) => <Icon {...p} d={<>
  <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
  <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
</>} />;

const Filter = (p) => <Icon {...p} d={<polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />} />;
const CreditCard = (p) => <Icon {...p} d={<>
  <rect width="20" height="14" x="2" y="5" rx="2" />
  <line x1="2" x2="22" y1="10" y2="10" />
</>} />;

window.CFIcons = {
  Wallet, Inbox, PieChartIcon, BarChart3, MoreHorizontal, Check, X, Split,
  Trash2, Link2, Search, Plus, Calendar, TagIcon, FolderIcon, ChevronDown,
  ChevronRight, ArrowLeft, Moon, Sun, Bell, Filter, CreditCard,
};
