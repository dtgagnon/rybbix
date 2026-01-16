"use client";

import { useIntersectionObserver } from "@uidotdev/usehooks";
import { useEffect } from "react";
import { useGetEventsInfinite } from "../../../../api/analytics/hooks/events/useGetEvents";
import { NothingFound } from "../../../../components/NothingFound";
import { formatter } from "../../../../lib/utils";
import { EventLogItem, EventLogItemSkeleton } from "./EventLogItem";
import { ErrorState } from "../../../../components/ErrorState";
import { ScrollArea } from "../../../../components/ui/scroll-area";

export function EventLog() {
  // Fetch events with infinite scrolling
  const { data, isLoading, isError, fetchNextPage, hasNextPage, isFetchingNextPage } = useGetEventsInfinite({
    pageSize: 100,
  });

  // Use the intersection observer hook
  const [ref, entry] = useIntersectionObserver({
    threshold: 0,
    root: null,
    rootMargin: "0px 0px 100px 0px",
  });

  // Fetch next page when intersection observer detects the target is visible
  useEffect(() => {
    if (entry?.isIntersecting && hasNextPage && !isFetchingNextPage && !isLoading) {
      fetchNextPage();
    }
  }, [entry?.isIntersecting, fetchNextPage, hasNextPage, isFetchingNextPage, isLoading]);

  // Flatten all pages of data
  const allEvents = data?.pages.flatMap(page => page.data) || [];

  if (isLoading) {
    return (
      <div className="space-y-2">
        {Array.from({ length: 100 }).map((_, index) => (
          <EventLogItemSkeleton key={index} />
        ))}
      </div>
    );
  }

  if (isError) {
    return (
      <ErrorState
        title="Failed to load events"
        message="There was a problem fetching the events. Please try again later."
      />
    );
  }

  if (allEvents.length === 0) {
    return <NothingFound title={"No events found"} description={"Try a different date range or filter"} />;
  }

  return (
    <ScrollArea className="h-[80vh]">
      <div className="h-full pr-2 overflow-x-hidden">
        {allEvents.map((event, index) => (
          <EventLogItem key={`${event.timestamp}-${index}`} event={event} />
        ))}

        {/* Infinite scroll sentinel */}
        <div ref={ref} className="py-2">
          {isFetchingNextPage && (
            Array.from({ length: 3 }).map((_, index) => (
              <EventLogItemSkeleton key={`next-page-${index}`} />
            ))
          )}
        </div>
      </div>
      {/* Pagination info */}
      {data?.pages[0]?.pagination && (
        <div className="text-center text-xs text-neutral-500 dark:text-neutral-400 pt-2">
          Showing {allEvents.length} of {formatter(data.pages[0].pagination.total)} events
        </div>
      )}
    </ScrollArea>
  );
}
