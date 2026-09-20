import { create } from "zustand";

interface UiState {
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
  toggleSidebar: () => void;
  /** The sport the dashboard reports on; null = the facility's first sport. */
  activeFacilitySportId: string | null;
  setActiveFacilitySportId: (id: string | null) => void;
}

export const useUiStore = create<UiState>((set) => ({
  sidebarOpen: false,
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  activeFacilitySportId: null,
  setActiveFacilitySportId: (id) => set({ activeFacilitySportId: id }),
}));