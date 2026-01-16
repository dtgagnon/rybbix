"use client";

import { Plus } from "lucide-react";
import { Button } from "../../../../components/ui/button";
import GoalFormModal from "./GoalFormModal";

interface CreateGoalButtonProps {
  siteId: number;
}

export default function CreateGoalButton({ siteId }: CreateGoalButtonProps) {
  return (
    <>
      <GoalFormModal
        siteId={siteId}
        trigger={
          <Button className="flex items-center gap-1">
            <Plus className="h-4 w-4" />
            <span>Add Goal</span>
          </Button>
        }
      />
    </>
  );
}
